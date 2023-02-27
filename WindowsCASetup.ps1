function Main() {
    Write-Output "Ecclesia IT Windows CA Setup 5 (27.02.2023)"
    Write-Output "=========================================================="
    CreateCAFile
    ConfigureCurl
    ConfigureGit
    ConfigureNode
    ConfigureDeno
    ConfigureJava
    ConfigureIntelliJIDEA
}

function CreateCAFile() {
    Write-Output "CA-File wird erstellt: $(Get-Variable cafile -ValueOnly)"
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
    
    Remove-Item -Path $cafile -ErrorAction SilentlyContinue
    
    Invoke-WebRequest -Uri "https://curl.haxx.se/ca/cacert.pem" -OutFile $cafile

    Write-Output "Ecclesia Holding GmbH AD Root CA" | Add-Content -Path $cafile
    Write-Output "================================" | Add-Content -Path $cafile
    Write-Output $root_ca | Add-Content -Path $cafile
    Write-Output "Ecclesia Holding GmbH AD Sub1 CA" | Add-Content -Path $cafile
    Write-Output "================================" | Add-Content -Path $cafile
    Write-Output $sub1_ca | Add-Content -Path $cafile
}

function ConfigureCurl() {
    if (Get-Command "curl" -ErrorAction SilentlyContinue) {
        Write-Output "Curl wird konfiguriert: CURL_CA_BUNDLE"
        [Environment]::SetEnvironmentVariable("CURL_CA_BUNDLE", $cafile, "User")
    }
}

function ConfigureGit() {
    if (Get-Command "git" -ErrorAction SilentlyContinue) {
        Write-Output "Git wird konfiguriert: http.sslcainfo"
        & git config --global --unset http.sslverify
        & git config --global http.sslcainfo "$cafile"
    }
}

function ConfigureNode() {
    if (Get-Command "node" -ErrorAction SilentlyContinue) {
        Write-Output "node.js wird konfiguriert: NODE_EXTRA_CA_CERTS"
        [Environment]::SetEnvironmentVariable("NODE_EXTRA_CA_CERTS", $cafile, "User")
    }
}

function ConfigureDeno() {
    if (Get-Command "deno" -ErrorAction SilentlyContinue) {
        Write-Output "Deno wird konfiguriert: DENO_TLS_CA_STORE"
        [Environment]::SetEnvironmentVariable("DENO_TLS_CA_STORE", "system", "User")
    }
}

function ConfigureJava() {
    Write-Output "Java wird konfiguriert: cacerts"

    $scoop_base_dir = "~/scoop/apps/"
    
    if (Test-Path $scoop_base_dir) {
        $scoop_javas = Get-ChildItem -Recurse -Path $scoop_base_dir -Depth 3 -Filter java.exe -File -Name | Select-String "current"

        for($i = 0; $i -le ($scoop_javas.count - 1); $i += 1) {
            $java_location = (get-item ($scoop_base_dir + $scoop_javas[$i])).Directory.Parent.FullName
            ConfigureJavaInstallation $java_location "Scoop"
        }
    }
    
    ConfigureJavaInstallation $env:JAVA_HOME "JAVA_HOME"
}

function ConfigureJavaInstallation($java_directory, $source) {
    $java_binary = "$java_directory\bin\java.exe"
    
    $root_ca_file = "$env:TEMP\root-ca.cer"
    $sub1_ca_file = "$env:TEMP\sub1-ca.cer"

    if (Test-Path $java_binary) {
        $root_ca | Out-File -Encoding ASCII -FilePath $root_ca_file
        $sub1_ca | Out-File -Encoding ASCII -FilePath $sub1_ca_file

        $java_version = (Get-Command $java_binary).Version.Major

        Write-Output "- $java_directory (Quelle: $source; Version $java_version)"

        ImportCert $java_directory $java_version $root_ca_file ecc_root-ca
        ImportCert $java_directory $java_version $sub1_ca_file ecc_sub1-ca

        Remove-Item $root_ca_file
        Remove-Item $sub1_ca_file
    }
}

function ImportCert($java_directory, $java_version, $ca_file, $ca_alias) {
    $keytool_binary = "$java_directory\bin\keytool.exe"
    $cacerts_file = "$java_directory\jre\lib\security\cacerts"
    
    if ($java_version -le 8) {
        $present = & $keytool_binary -keystore "$cacerts_file" -storepass "changeit" -list | Select-String -Quiet -Pattern "$ca_alias"
    } else {
        $present = & $keytool_binary -cacerts -storepass "changeit" -list | Select-String -Quiet -Pattern "$ca_alias"
    }

    if ($present) {
        return
    }
    
    if ($java_version -le 8) {
        & $keytool_binary -importcert -keystore "$cacerts_file" -storepass "changeit" -trustcacerts -noprompt -alias "$ca_alias" -file "$ca_file"
    }  else {
        & $keytool_binary -importcert -storepass "changeit" -cacerts -noprompt -alias "$ca_alias" -file "$ca_file"
    } 
}

function ConfigureIntelliJIDEA() {
    $jetbrains_root_dir = "$env:APPDATA\Jetbrains"
    if (!(Test-Path $jetbrains_root_dir)) {
        return
    }

    $intellij_dirs = Get-ChildItem $jetbrains_root_dir "IntellijIdea*" -Recurse -Directory
    if ($intellij_dirs.count -eq 0) {
        return
    }

    Write-Output "IntelliJ IDEA wird konfiguriert:"

    if (!(Test-Path $env:JAVA_HOME)) {
        Write-Output "! Kein Java gefunden. JAVA_HOME gesetzt?"
        return
    }

    $src_cacerts_files = Get-ChildItem $env:JAVA_HOME "cacerts" -Recurse -File
    if ($src_cacerts_files.count -ne 1) {
        Write-Output "! Es darf nur genau eine cacerts-Datei in der Java-Installation vorhanden sein"
        return
    }
    $src_cacerts_file = $src_cacerts_files[0]

    foreach ($intellij_dir in $intellij_dirs) {
        $ssl_dir = "$intellij_dir\ssl"
        $dst_cacert_file = "$ssl_dir\cacerts"
        
        Write-Output $ssl_dir

        if (Test-Path $ssl_dir) {
            Write-Output "- $($intellij_dir.BaseName)"
            Copy-Item -Path $src_cacerts_file.FullName -Destination $dst_cacert_file            
        }      
    }
}

function ReadMachineCert ($certPath) {
    $MachineCert = Get-ChildItem -path "$certPath" -Recurse | Select-Object -First 1
    $Pem = new-object System.Text.StringBuilder
    $Pem.AppendLine("-----BEGIN CERTIFICATE-----")
    $Pem.AppendLine([System.Convert]::ToBase64String($MachineCert.RawData, 1))
    $Pem.AppendLine("-----END CERTIFICATE-----")
    $PemString = $Pem.ToString()
    return $PemString
}

$cafile = "$env:USERPROFILE\ecclesia_cafile.pem"

$root_ca = (ReadMachineCert 'Cert:\*56BD703E9E5A912012577B00DF6E313779EAC6AD')[-1]
$sub1_ca = (ReadMachineCert 'Cert:\*8E997E9990e89EA4BB03C6379179A9FB4EC26D7F')[-1] 

Main