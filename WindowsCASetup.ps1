function Main() {
    Write-Output "Ecclesia IT Windows CA Setup 6 (17.11.2023)"
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
    
    Remove-Item -Path $caFile -ErrorAction SilentlyContinue
    
    Invoke-WebRequest -Uri "https://curl.haxx.se/ca/cacert.pem" -OutFile $caFile

    Write-Output "Ecclesia Holding GmbH AD Root CA" | Add-Content -Path $caFile
    Write-Output "================================" | Add-Content -Path $caFile
    Write-Output $rootCa | Add-Content -Path $caFile
    Write-Output "Ecclesia Holding GmbH AD Sub1 CA" | Add-Content -Path $caFile
    Write-Output "================================" | Add-Content -Path $caFile
    Write-Output $sub1Ca | Add-Content -Path $caFile
}

function ConfigureCurl() {
    if (Get-Command "curl" -ErrorAction SilentlyContinue) {
        Write-Output "Curl wird konfiguriert: CURL_CA_BUNDLE"
        [Environment]::SetEnvironmentVariable("CURL_CA_BUNDLE", $caFile, "User")
    }
}

function ConfigureGit() {
    if (Get-Command "git" -ErrorAction SilentlyContinue) {
        Write-Output "Git wird konfiguriert: http.sslcainfo"
        & git config --global --unset http.sslverify
        & git config --global http.sslcainfo "$caFile"
    }
}

function ConfigureNode() {
    if (Get-Command "node" -ErrorAction SilentlyContinue) {
        Write-Output "node.js wird konfiguriert: NODE_EXTRA_CA_CERTS"
        [Environment]::SetEnvironmentVariable("NODE_EXTRA_CA_CERTS", $caFile, "User")
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

    $scoopBaseDir = "~/scoop/apps/"
    
    if (Test-Path $scoopBaseDir) {
        $scoopJavas = Get-ChildItem -Recurse -Path $scoopBaseDir -Depth 7 -Filter java.exe -File -Name | Select-String "current"

        for($i = 0; $i -le ($scoopJavas.count - 1); $i += 1) {
            $javaLocation = (get-item ($scoopBaseDir + $scoopJavas[$i])).Directory.Parent.FullName
            ConfigureJavaInstallation $javaLocation "Scoop"
        }
    }
    
    ConfigureJavaInstallation $env:JAVA_HOME "JAVA_HOME"
    
    $temurinDir = $env:ProgramFiles + "\Eclipse Adoptium\"

    if (Test-Path $temurinDir) {
        $temurinJavas = Get-ChildItem -Recurse -Path $temurinDir -Depth 2 -Filter java.exe -File -Name
    
        for($i = 0; $i -le ($temurinJavas.count - 1); $i += 1) {
            $javaLocation = (get-item ($temurinDir + $temurinJavas[$i])).Directory.Parent.FullName
            ConfigureJavaInstallation $javaLocation "Eclipse Temurin"
        }
    }
}

function ConfigureJavaInstallation($javaDirectory, $source) {
    $javaBinary = "$javaDirectory\bin\java.exe"
    
    $rootCaFile = "$env:TEMP\root-ca.cer"
    $sub1CaFile = "$env:TEMP\sub1-ca.cer"

    if (Test-Path $javaBinary) {
        $rootCa | Out-File -Encoding ASCII -FilePath $rootCaFile
        $sub1Ca | Out-File -Encoding ASCII -FilePath $sub1CaFile

        $javaVersion = (Get-Command $javaBinary).Version.Major

        Write-Output "- $javaDirectory (Quelle: $source; Version $javaVersion)"

        ImportCert $javaDirectory $javaVersion $rootCaFile ecc_root-ca
        ImportCert $javaDirectory $javaVersion $sub1CaFile ecc_sub1-ca

        Remove-Item $rootCaFile
        Remove-Item $sub1CaFile
    }
}

function ImportCert($javaDirectory, $javaVersion, $caFile, $caAlias) {
    $keytoolBinary = "$javaDirectory\bin\keytool.exe"
    $cacertsFile = "$javaDirectory\jre\lib\security\cacerts"
    
    if ($javaVersion -le 8) {
        $present = & $keytoolBinary -keystore "$cacertsFile" -storepass "changeit" -list | Select-String -Quiet -Pattern "$caAlias"
    } else {
        $present = & $keytoolBinary -cacerts -storepass "changeit" -list | Select-String -Quiet -Pattern "$caAlias"
    }

    if ($present) {
        return
    }
    
    if ($javaVersion -le 8) {
        & $keytoolBinary -importcert -keystore "$cacertsFile" -storepass "changeit" -trustcacerts -noprompt -alias "$caAlias" -file "$caFile"
    }  else {
        & $keytoolBinary -importcert -storepass "changeit" -cacerts -noprompt -alias "$caAlias" -file "$caFile"
    } 
}

function ConfigureIntelliJIDEA() {
    $jetbrainsRootDir = "$env:APPDATA\Jetbrains"
    if (!(Test-Path $jetbrainsRootDir)) {
        return
    }

    $intellijDirs = Get-ChildItem $jetbrainsRootDir "IntellijIdea*" -Recurse -Directory
    if ($intellijDirs.count -eq 0) {
        return
    }

    Write-Output "IntelliJ IDEA wird konfiguriert:"

    if (!(Test-Path $env:JAVA_HOME)) {
        Write-Output "! Kein Java gefunden. JAVA_HOME gesetzt?"
        return
    }

    $srcCacertsFiles = Get-ChildItem $env:JAVA_HOME "cacerts" -Recurse -File
    if ($srcCacertsFiles.count -ne 1) {
        Write-Output "! Es darf nur genau eine cacerts-Datei in der Java-Installation vorhanden sein"
        return
    }
    $srcCacertsFile = $srcCacertsFiles[0]

    foreach ($intellijDir in $intellijDirs) {
        $sslDir = "$intellijDir\ssl"
        $dstCacertsFile = "$sslDir\cacerts"
        
        Write-Output $sslDir

        if (Test-Path $sslDir) {
            Write-Output "- $($intellijDir.BaseName)"
            Copy-Item -Path $srcCacertsFile.FullName -Destination $dstCacertsFile            
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

$caFile = "$env:USERPROFILE\ecclesia_cafile.pem"

$rootCa = (ReadMachineCert 'Cert:\*56BD703E9E5A912012577B00DF6E313779EAC6AD')[-1]
$sub1Ca = (ReadMachineCert 'Cert:\*8E997E9990e89EA4BB03C6379179A9FB4EC26D7F')[-1] 

Main
