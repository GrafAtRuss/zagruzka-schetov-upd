# Установка расширения ЗагрузкаСчетовУПД в базу Бухгалтерии.
# Запуск: InstallExtension.bat
# Конфигуратор стартует на этом компьютере и загружает расширение в выбранную базу.

$ErrorActionPreference = "Stop"
try { chcp 65001 > $null } catch {}
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$SettingsFile = Join-Path $Root "установка.настройки.json"
$ExtName = "ЗагрузкаСчетовУПД"
$Cfe = Join-Path $Root "ЗагрузкаСчетовУПД_1.0.6.cfe"

function Write-Title([string]$Text) {
    Write-Host ""
    Write-Host $Text -ForegroundColor Cyan
}

function Read-OrDefault([string]$Prompt, [string]$Default) {
    $suffix = ""
    if ($Default) { $suffix = " [$Default]" }
    $value = Read-Host "$Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value.Trim()
}

function Read-Choice([string]$Prompt, [string[]]$Options, [int]$DefaultIndex) {
    Write-Host $Prompt
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $mark = " "
        if ($i -eq $DefaultIndex) { $mark = "*" }
        Write-Host ("  {0}{1}) {2}" -f $mark, ($i + 1), $Options[$i])
    }
    $raw = Read-Host "Номер"
    if ([string]::IsNullOrWhiteSpace($raw)) { return $DefaultIndex }
    $n = 0
    if (-not [int]::TryParse($raw.Trim(), [ref]$n)) { return $DefaultIndex }
    $n = $n - 1
    if ($n -lt 0 -or $n -ge $Options.Count) { return $DefaultIndex }
    return $n
}

function Read-YesNo([string]$Prompt, [bool]$DefaultYes) {
    $hint = $(if ($DefaultYes) { "Y/n" } else { "y/N" })
    $raw = Read-Host "$Prompt ($hint)"
    if ([string]::IsNullOrWhiteSpace($raw)) { return $DefaultYes }
    return $raw.Trim().ToLower() -match '^(y|д|yes|да)$'
}

function Find-Platforms {
    $roots = @(
        (Join-Path $env:ProgramFiles "1cv8"),
        (Join-Path ${env:ProgramFiles(x86)} "1cv8")
    ) | Where-Object { $_ -and (Test-Path $_) }
    $found = @()
    foreach ($dir in $roots) {
        $found += Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+' } |
            ForEach-Object {
                $exe = Join-Path $_.FullName "bin\1cv8.exe"
                if (Test-Path $exe) { $exe }
            }
    }
    $found | Sort-Object -Descending {
        if ($_ -match '\\(\d+)\.(\d+)\.(\d+)\.(\d+)\\') {
            return [version]("$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])")
        }
        return [version]"0.0.0.0"
    }
}

function Unprotect-Password([string]$Stored) {
    if ([string]::IsNullOrWhiteSpace($Stored)) { return "" }
    try {
        $secure = ConvertTo-SecureString $Stored
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    } catch { return "" }
}

function Protect-Password([string]$Plain) {
    if ([string]::IsNullOrEmpty($Plain)) { return "" }
    $secure = ConvertTo-SecureString $Plain -AsPlainText -Force
    return ConvertFrom-SecureString $secure
}

function Read-Log([string]$Path) {
    if (-not (Test-Path $Path)) { return "" }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { return "" }
    $candidates = @()
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
        $candidates += [System.Text.Encoding]::Unicode.GetString($bytes)
    } elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        $candidates += [System.Text.Encoding]::UTF8.GetString($bytes)
    } else {
        $candidates += [System.Text.Encoding]::GetEncoding(1251).GetString($bytes)
        $candidates += [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    $best = ""
    $bestScore = -1
    foreach ($text in $candidates) {
        $score = ([regex]::Matches($text, "[А-Яа-яЁё]")).Count
        if ($score -gt $bestScore) {
            $best = $text
            $bestScore = $score
        }
    }
    return $best
}

function Test-StepOk($Result) {
    $text = [string]$Result.Text
    if ($text -match "Ошибка|не выполн|Не удалось|не найден|не может быть|Конфликт") { return $false }
    if ($Result.Code -ne 0) { return $false }
    if ($text -match "успешно|завершена|Загрузка конфигурации из файлов") { return $true }
    if ([string]::IsNullOrWhiteSpace($text)) { return $true }
    return $true
}

function Show-LogTail([string]$Text, [string]$Path) {
    Write-Title "Журнал"
    Write-Host $Path
    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-Host "(файл журнала пуст или не создан)"
        return
    }
    ($Text -split "\r?\n" | Select-Object -Last 40) | ForEach-Object { Write-Host $_ }
}

function Format-DesignerArg([string]$Arg) {
    if ($Arg -match '[\s"]' -or $Arg -match '[^\x00-\x7F]') {
        return '"' + ($Arg -replace '"', '\"') + '"'
    }
    return $Arg
}

function Invoke-Designer([string]$Platform, [string[]]$Arguments, [string]$LogPath) {
    if (Test-Path $LogPath) { Remove-Item $LogPath -Force }
    $line = ($Arguments | ForEach-Object { Format-DesignerArg $_ }) -join " "
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Platform
    $psi.Arguments = $line
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $proc.WaitForExit()
    $text = Read-Log $LogPath
    Show-LogTail $text $LogPath
    return @{ Code = $proc.ExitCode; Text = $text }
}

function Copy-Dump([string]$Source) {
    # Путь с кириллицей 1С часто не считает каталогом выгрузки.
    $dest = Join-Path $env:TEMP "ZagruzkaSchetovUPD"
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest | Out-Null
    $skip = @(".git", "dist", "load.log", "update.log", "dump.log", "установка.настройки.json")
    Get-ChildItem -LiteralPath $Source -Force | Where-Object { $skip -notcontains $_.Name -and $_.Extension -ne ".cfe" } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Recurse -Force
    }
    if (-not (Test-Path (Join-Path $dest "Configuration.xml"))) { throw "В копии нет Configuration.xml" }
    if (-not (Test-Path (Join-Path $dest "ConfigDumpInfo.xml"))) { throw "В копии нет ConfigDumpInfo.xml" }
    return $dest
}

if (-not (Test-Path (Join-Path $Root "Configuration.xml"))) {
    $nested = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "Configuration.xml") } |
        Select-Object -First 1
    if ($nested) { $Root = $nested.FullName }
}
if (-not (Test-Path (Join-Path $Root "Configuration.xml"))) {
    Write-Host "Рядом со скриптом нет Configuration.xml." -ForegroundColor Red
    Write-Host "Нужен каталог, внутри которого лежит Configuration.xml. Не zip и не папка уровнем выше." -ForegroundColor Red
    Write-Host "Сейчас: $Root"
    exit 1
}

$saved = $null
if (Test-Path $SettingsFile) {
    try { $saved = Get-Content $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $saved = $null }
}

Write-Title "Установка расширения «Загрузка счетов и УПД» в Бухгалтерию"
Write-Host "Скрипт спросит базу и загрузит расширение. Конфигурация Бухгалтерии не меняется."
Write-Host "Ответы запоминаются. Пароль хранится шифром Windows только для этого пользователя."

$platforms = @(Find-Platforms)
$platformOptions = @()
foreach ($exe in $platforms) { $platformOptions += $exe }
$platformOptions += "Указать путь к 1cv8.exe вручную"
$defaultPlatform = 0
if ($saved.Platform) {
    $idx = [array]::IndexOf($platformOptions, [string]$saved.Platform)
    if ($idx -ge 0) { $defaultPlatform = $idx }
}
$platformChoice = Read-Choice "Платформа 1С (та же версия, что у сервера):" $platformOptions $defaultPlatform
if ($platformChoice -eq ($platformOptions.Count - 1)) {
    $platform = Read-OrDefault "Полный путь к 1cv8.exe" $(if ($saved.Platform) { [string]$saved.Platform } else { "" })
} else {
    $platform = $platformOptions[$platformChoice]
}
if (-not (Test-Path $platform)) {
    Write-Host "Файл платформы не найден: $platform" -ForegroundColor Red
    exit 1
}

$modeOptions = @("Файловая база", "Сервер приложений (кластер)")
$defaultMode = 1
if ($saved.Mode -eq "file") { $defaultMode = 0 }
$modeChoice = Read-Choice "Где находится база Бухгалтерии:" $modeOptions $defaultMode
$mode = "server"
$server = ""
$port = ""
$baseName = ""
$basePath = ""
if ($modeChoice -eq 0) {
    $mode = "file"
    $basePath = Read-OrDefault "Каталог файловой базы" $(if ($saved.BasePath) { [string]$saved.BasePath } else { "" })
    if (-not (Test-Path $basePath)) {
        Write-Host "Каталог базы не найден: $basePath" -ForegroundColor Red
        exit 1
    }
    $connection = $basePath
} else {
    $server = Read-OrDefault "Сервер кластера (имя или IP)" $(if ($saved.Server) { [string]$saved.Server } else { "" })
    $port = Read-OrDefault "Порт кластера (пусто = 1541)" $(if ($saved.Port) { [string]$saved.Port } else { "" })
    $baseName = Read-OrDefault "Имя базы на сервере" $(if ($saved.BaseName) { [string]$saved.BaseName } else { "" })
    if ([string]::IsNullOrWhiteSpace($server) -or [string]::IsNullOrWhiteSpace($baseName)) {
        Write-Host "Нужны сервер и имя базы." -ForegroundColor Red
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($port) -or $port -eq "1541") {
        $connection = "$server\$baseName"
    } else {
        $connection = "${server}:$port\$baseName"
    }
}

$authOptions = @("Пользователь 1С", "Вход Windows")
$defaultAuth = 0
if ($saved.Auth -eq "windows") { $defaultAuth = 1 }
$authChoice = Read-Choice "Как входить в базу:" $authOptions $defaultAuth
$auth = "user"
$userName = ""
$password = ""
if ($authChoice -eq 1) {
    $auth = "windows"
} else {
    $userName = Read-OrDefault "Пользователь" $(if ($saved.User) { [string]$saved.User } else { "" })
    $storedPassword = Unprotect-Password $(if ($saved.PasswordProtected) { [string]$saved.PasswordProtected } else { "" })
    $secure = Read-Host "Пароль (пустой ввод оставляет сохраненный)" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    if ([string]::IsNullOrEmpty($password)) { $password = $storedPassword }
}

Write-Title "Проверьте"
Write-Host "Платформа : $platform"
Write-Host "Подключение: $connection"
Write-Host "Расширение: $ExtName"
Write-Host "Вход     : $(if ($auth -eq 'windows') { 'Windows' } else { $userName })"
if (-not (Read-YesNo "Загрузить расширение в эту базу?" $true)) {
    Write-Host "Отменено."
    exit 0
}

$common = @("DESIGNER", "/DisableStartupDialogs")
if ($mode -eq "file") { $common += @("/F", $connection) } else { $common += @("/S", $connection) }
if ($auth -eq "windows") { $common += "/WA+" } else { $common += @("/N", $userName, "/P", $password, "/WA-") }

Write-Title "Каталог выгрузки"
$dump = Copy-Dump $Root
Write-Host $dump
$logLoad = Join-Path $Root "load.log"
Write-Title "Загрузка расширения из файлов"
$loadArgs = $common + @("/LoadConfigFromFiles", $dump, "-Format", "Hierarchical", "-Extension", $ExtName, "/Out", $logLoad)
$load = Invoke-Designer $platform $loadArgs $logLoad
$loadOk = Test-StepOk $load
if (-not $loadOk) {
    Write-Host "Загрузка не выполнена. Код: $($load.Code)" -ForegroundColor Yellow
    Write-Host "Полный журнал: $logLoad"
    if ($load.Text -match "не найден") {
        Write-Host "Создайте в конфигураторе пустое расширение с именем $ExtName (Конфигурация - Расширения конфигурации - Добавить) и запустите скрипт снова." -ForegroundColor Yellow
    }
    if ($load.Text -match "Русский|ОбъектРасширяемойКонфигурации") {
        Write-Host "В расширении откройте язык Русский, в поле объекта расширяемой конфигурации выберите Русский (F4) и обновите конфигурацию базы." -ForegroundColor Yellow
    }
    exit 1
}
Write-Host "Файлы расширения загружены." -ForegroundColor Green

$logDb = Join-Path $Root "update.log"
Write-Title "Обновление расширения в базе"
$dbArgs = $common + @("/UpdateDBCfg", "-Extension", $ExtName, "-Dynamic+", "/Out", $logDb)
$db = Invoke-Designer $platform $dbArgs $logDb
$dbOk = Test-StepOk $db
if (-not $dbOk) {
    Write-Title "Повтор без динамического обновления"
    $dbArgs2 = $common + @("/UpdateDBCfg", "-Extension", $ExtName, "-SessionTerminate", "prompt", "/Out", $logDb)
    $db = Invoke-Designer $platform $dbArgs2 $logDb
    $dbOk = Test-StepOk $db
}
if (-not $dbOk) {
    Write-Host "База расширения не обновлена. Код: $($db.Code). Откройте конфигуратор и обновите конфигурацию базы данных расширения вручную." -ForegroundColor Yellow
    exit 1
}
Write-Host "Расширение записано в базу." -ForegroundColor Green

$logCfe = Join-Path $Root "dump.log"
Write-Title "Файл cfe для других баз"
$cfeArgs = $common + @("/DumpCfg", $Cfe, "-Extension", $ExtName, "/Out", $logCfe)
$cfeRun = Invoke-Designer $platform $cfeArgs $logCfe
if (Test-Path $Cfe) {
    Write-Host "Файл: $Cfe" -ForegroundColor Green
    Write-Host "В другой базе: Конфигурация, Расширения конфигурации, Загрузить из файла."
} else {
    Write-Host "cfe не создан. В этой базе расширение уже стоит, файл можно снять позже." -ForegroundColor Yellow
}

$toSave = [ordered]@{
    Platform = $platform
    Mode = $mode
    BasePath = $(if ($mode -eq "file") { $basePath } else { $(if ($saved.BasePath) { [string]$saved.BasePath } else { "" }) })
    Server = $(if ($mode -eq "server") { $server } else { $(if ($saved.Server) { [string]$saved.Server } else { "" }) })
    Port = $(if ($mode -eq "server") { $port } else { $(if ($saved.Port) { [string]$saved.Port } else { "" }) })
    BaseName = $(if ($mode -eq "server") { $baseName } else { $(if ($saved.BaseName) { [string]$saved.BaseName } else { "" }) })
    Auth = $auth
    User = $userName
    PasswordProtected = $(if ($auth -eq "user") { Protect-Password $password } else { "" })
}
$toSave | ConvertTo-Json | Set-Content -Path $SettingsFile -Encoding UTF8
Write-Host ""
Write-Host "Дальше:"
Write-Host "1. В списке расширений снимите «Безопасный режим» и «Защита от опасных действий»."
Write-Host "2. Пользователям, которые загружают счета, назначьте роль «Загрузка счетов и УПД из PDF»."
Write-Host "   Роль сама никому не выдается. Без нее раздела нет."
Write-Host "3. Перезапустите 1С. В панели разделов будет «Загрузка PDF»."
exit 0
