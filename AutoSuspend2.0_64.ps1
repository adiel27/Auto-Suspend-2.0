# Path to PsSuspend executable
$PsSuspendPath = "C:\PsTools\PsSuspend64.exe"

# Path untuk log file
$LogFilePath = "C:\SuspendLog.txt"

# Threshold untuk suspend jika masih idle setelah idle set (5 menit tambahan)
$SuspendThreshold = 300 # 5 minutes

# Interval pemeriksaan
$CheckInterval = 10 # seconds

# List of processes to exclude (important system, driver, and security processes)
$ExcludedProcesses = @("System", "svchost", "explorer", "wininit", "csrss", "services", "lsass", 
                       "igfx", "amddvr", "RadeonSoftware", "DolbyDAX2", "DolbyCPL", "MsMpEng")

# List to keep track of suspended processes
$SuspendedProcesses = @()

# List to track idle processes
$IdleProcesses = @{}

# Import module for Windows toast notifications
Import-Module BurntToast

# Display startup notification
New-BurntToastNotification -Text "Suspender script berjalan", "Skrip otomatis sedang aktif. Anda dapat memeriksa log di $LogFilePath untuk informasi lebih lanjut."

# Hide PowerShell window (run script in background)
$PSWindow = Get-Process -Id $PID
$PSWindow.CloseMainWindow()

while ($true) {
    # Get list of running processes with window titles
    $Processes = Get-Process | Where-Object { $_.MainWindowTitle -ne "" }
    $SuspendCount = 0 # Counter jumlah aplikasi yang disuspend dalam satu loop

    foreach ($Process in $Processes) {
        try {
            # Skip excluded processes
            if ($ExcludedProcesses -contains $Process.ProcessName) {
                continue
            }

            # Check if process is already suspended
            if ($SuspendedProcesses -contains $Process.Id) {
                # Check if user interacts with the process
                $IsActive = $Process.MainWindowHandle -ne 0

                if ($IsActive) {
                    # Resume the process
                    Start-Process -FilePath $PsSuspendPath -ArgumentList "-r $Process.Id" -NoNewWindow -Wait
                    Write-Host "$($Process.Name) has been resumed."
                    
                    # Log resume status
                    "$($Process.Name) [PID: $($Process.Id)] has been resumed at $(Get-Date)" | Out-File -Append $LogFilePath

                    $SuspendedProcesses = $SuspendedProcesses | Where-Object { $_ -ne $Process.Id }
                    $IdleProcesses.Remove($Process.Id) # Hapus dari daftar idle
                }
                continue
            }

            # Check CPU usage to detect idle state
            $CPUUsage = (Get-Counter "\Process($($Process.ProcessName))\% Processor Time").CounterSamples.CookedValue

            if ($CPUUsage -lt 20 -and $Process.MainWindowHandle -ne 0) {
                # Set priority ke Idle jika CPU usage < 20%
                $Process.PriorityClass = "Idle"
                Write-Host "$($Process.Name) telah diturunkan ke prioritas Idle."
                
                # Log perubahan prioritas
                "$($Process.Name) [PID: $($Process.Id)] priority set to Idle at $(Get-Date)" | Out-File -Append $LogFilePath
            }

            if ($CPUUsage -eq 0 -and $Process.MainWindowHandle -ne 0) {
                # Cek apakah sudah masuk dalam daftar idle
                if ($IdleProcesses.ContainsKey($Process.Id)) {
                    $IdleTime = $(Get-Date) - $IdleProcesses[$Process.Id]
                    
                    if ($IdleTime.TotalSeconds -ge $SuspendThreshold) {
                        # Suspend the process
                        Start-Process -FilePath $PsSuspendPath -ArgumentList "$Process.Id" -NoNewWindow -Wait
                        Write-Host "$($Process.Name) has been suspended."

                        # Log suspend status
                        "$($Process.Name) [PID: $($Process.Id)] has been suspended at $(Get-Date)" | Out-File -Append $LogFilePath

                        $SuspendedProcesses += $Process.Id
                        $SuspendCount++ # Tambah jumlah aplikasi yang terkena suspend
                    }
                } else {
                    # Tandai proses sebagai idle baru
                    $IdleProcesses[$Process.Id] = Get-Date
                }
            } else {
                # Hapus dari daftar idle jika ada aktivitas
                if ($IdleProcesses.ContainsKey($Process.Id)) {
                    $IdleProcesses.Remove($Process.Id)
                }
            }
        } catch {
            Write-Warning "Cannot access data for $($Process.Name)"
        }
    }

    # Jika ada aplikasi yang disuspend, tampilkan notifikasi dengan jumlahnya
    if ($SuspendCount -gt 0) {
        New-BurntToastNotification -Text "Suspender script", "$SuspendCount aplikasi telah dibekukan karena idle. Anda dapat memeriksa log di $LogFilePath untuk informasi lebih lanjut."
    }

    Start-Sleep -Seconds $CheckInterval
}
