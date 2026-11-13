# Telegram-бот для связи с ПК.
# Входящие сообщения печатаются в терминал, ответы отправляются обратно в Telegram.
# Токен сохраняется в bot-token.txt рядом со скриптом (вводится один раз).

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::GetEncoding(866)
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tokenFile = Join-Path $scriptDir "bot-token.txt"

if (-not (Test-Path $tokenFile)) {
    $token = Read-Host "Введите токен бота (от @BotFather)"
    $token.Trim() | Set-Content -Path $tokenFile -NoNewline -Encoding UTF8
} else {
    $token = (Get-Content $tokenFile -Raw).Trim()
}

if (-not $token) {
    Write-Host "Токен пуст. Выход." -ForegroundColor Red
    exit 1
}

$api = "https://api.telegram.org/bot$token"
$offset = 0
$lastChatId = $null
$lastUser = $null
$knownChats = @{}
$inputBuffer = ''

Write-Host ""
Write-Host "===== Telegram-бот запущен =====" -ForegroundColor Green
Write-Host "Входящие сообщения будут появляться ниже." -ForegroundColor Green
Write-Host "Как отвечать:" -ForegroundColor Yellow
Write-Host "  - просто введите текст -> ответит последнему собеседнику" -ForegroundColor Yellow
Write-Host "  - /to <chat_id> <текст> -> ответить конкретному чату" -ForegroundColor Yellow
Write-Host "  - /chats -> показать последний чат" -ForegroundColor Yellow
Write-Host "  - /quit -> выход" -ForegroundColor Yellow
Write-Host ""

while ($true) {
    # Опрос обновлений
    try {
        $resp = Invoke-RestMethod -Uri "$api/getUpdates?offset=$offset&timeout=0" -Method Get -TimeoutSec 5
        if ($resp.ok -and $resp.result.Count -gt 0) {
            foreach ($u in $resp.result) {
                $offset = $u.update_id + 1
                if ($u.message) {
                    $m = $u.message
                    $chatId = $m.chat.id
                    $from = $m.from.username
                    if (-not $from) { $from = $m.from.first_name }
                    if (-not $from) { $from = "unknown" }
                    $text = $m.text
                    if ($null -eq $text) { $text = "[не текст]" }
                    $lastChatId = $chatId
                    $lastUser = $from
                    $knownChats[$chatId] = $from
                    $time = (Get-Date).ToString("HH:mm:ss")
                    Write-Host "[$time] [$from] (chat $chatId): $text" -ForegroundColor Cyan
                }
            }
        }
    } catch {
        Write-Host "Ошибка сети: $($_.Exception.Message)" -ForegroundColor Red
        Start-Sleep -Seconds 2
    }

    # Чтение ввода посимвольно (ReadKey)
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') {
            $line = $inputBuffer
            $inputBuffer = ''
            Write-Host ""
            if ($null -ne $line -and $line -ne '') {
            if ($line -eq "/quit") { break }
            if ($line -eq "/chats") {
                Write-Host "Последний чат: $lastChatId ($lastUser)" -ForegroundColor Magenta
                foreach ($k in $knownChats.Keys) { Write-Host "  $k -> $($knownChats[$k])" -ForegroundColor Magenta }
                continue
            }
            $target = $lastChatId
            $msg = $line
            if ($line -match '^/to\s+(\S+)\s+(.+)$') {
                $target = $matches[1]
                $msg = $matches[2]
            }
            if (-not $target) {
                Write-Host "Нет получателя. Дождитесь сообщения." -ForegroundColor Red
                continue
            }
            Write-Host "DEBUG: target=$target (type=$($target.GetType().Name)), msg='$msg'" -ForegroundColor DarkGray
            try { $target = [long]$target } catch { Write-Host "DEBUG: не удалось конвертировать в long" -ForegroundColor DarkGray }
            if (-not $msg) {
                Write-Host "Пустое сообщение." -ForegroundColor Red
                continue
            }
            try {
                $body = @{ chat_id = $target; text = $msg } | ConvertTo-Json -Compress
                Write-Host "DEBUG: body=$body" -ForegroundColor DarkGray
                Invoke-RestMethod -Uri "$api/sendMessage" -Method Post -Body $body -ContentType "application/json; charset=utf-8" | Out-Null
                Write-Host "[Вы -> $target]: $msg" -ForegroundColor Green
            } catch {
                $ex = $_.Exception
                Write-Host "Не удалось отправить: $($ex.Message)" -ForegroundColor Red
                if ($ex.Response) {
                    try {
                        $stream = $ex.Response.GetResponseStream()
                        $reader = New-Object System.IO.StreamReader($stream)
                        $detail = $reader.ReadToEnd()
                        Write-Host "Детали: $detail" -ForegroundColor Red
                    } catch {
                        Write-Host "Не удалось прочитать детали: $($_.Exception.Message)" -ForegroundColor Red
                    }
                } else {
                    Write-Host "Ответ сервера отсутствует" -ForegroundColor Red
                }
            }
        }
        } elseif ($key.Key -eq 'Backspace') {
            if ($inputBuffer.Length -gt 0) {
                $inputBuffer = $inputBuffer.Substring(0, $inputBuffer.Length - 1)
                Write-Host -NoNewline "`b `b"
            }
        } elseif ($key.KeyChar -ne [char]0) {
            $inputBuffer += $key.KeyChar
            Write-Host -NoNewline $key.KeyChar
        }
    }

    Start-Sleep -Milliseconds 400
}

Write-Host "Бот остановлен." -ForegroundColor Yellow
