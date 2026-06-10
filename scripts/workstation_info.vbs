Option Explicit
'
' ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
' ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
' ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
' ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
' ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
' ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
' ================================================================================
'  SCRIPT   : Workstation Information Popup                               v1.1.0
'  AUTHOR   : Limehawk.io
'  DATE     : June 2026
'  USAGE    : wscript.exe workstation_info.vbs   (popup mode — default)
'             cscript.exe workstation_info.vbs   (console mode)
' ================================================================================
'  FILE     : workstation_info.vbs
'  DESCRIPTION : Displays a popup with OS, computer, hardware, and network info
' --------------------------------------------------------------------------------
'  README
' --------------------------------------------------------------------------------
'  PURPOSE
'
'    Displays a popup message box showing system information to the end user.
'    Designed to be triggered from the RMM tray icon for user self-service so a
'    person can read their own machine name, serial, and specs without opening
'    a ticket.
'
'  DATA SOURCES & PRIORITY
'
'    - WMI root\cimv2 (local): Win32_OperatingSystem, Win32_ComputerSystem,
'      Win32_Processor, Win32_PhysicalMemory, Win32_NetworkAdapterConfiguration,
'      Win32_BIOS
'    - WScript.Network: current username
'
'  REQUIRED INPUTS
'
'    None. This script collects local system state and takes no configuration.
'
'  SETTINGS
'
'    - Output host: wscript.exe renders a MsgBox popup; cscript.exe prints to
'      stdout. The tray trigger uses wscript (popup) by default.
'
'  BEHAVIOR
'
'    The script performs the following actions in order:
'    1. Connects to the local WMI service (hard-fails if unreachable)
'    2. Queries OS, computer, CPU, memory, BIOS, and network adapter info
'    3. Renders a formatted summary via MsgBox (popup) or WScript.Echo (console)
'    4. Exits 0 on success, 1 on any collection failure
'
'  PREREQUISITES
'
'    - Windows 10/11 with Windows Script Host enabled
'    - No special privileges required (local WMI read)
'
'  SECURITY NOTES
'
'    - No secrets in logs — displays only non-sensitive inventory data
'    - Read-only; makes no system changes
'
'  ENDPOINTS
'
'    - Not applicable (all WMI queries are local)
'
'  EXIT CODES
'
'    0 = Success
'    1 = Failure (WMI connection or query error)
'
'  EXAMPLE RUN
'
'    A MsgBox dialog appears titled "Workstation Information" listing the OS,
'    computer name, current user, serial number, CPU, RAM, and network adapters.
'
' --------------------------------------------------------------------------------
'  CHANGELOG
' --------------------------------------------------------------------------------
'  2026-06-10 v1.1.0 Framework compliance: Option Explicit, ASCII header, full
'                    README, WMI error handling, declared all variables
'  2024-12-01 v1.0.0 Initial release - migrated from SuperOps
' ================================================================================

Dim objWMIService, objNetwork
Dim colOS, objOS, os_name, os_version
Dim colComputer, objComputer, computer_name, current_user
Dim colCPU, objCPU, cpu_name, cpu_cores
Dim colMemory, objMemory, total_ram
Dim colNetworkAdapters, objNetworkAdapter, network_adapters
Dim colBIOS, objBIOS, serial_number
Dim report

' Connect to the local WMI service (hard-fail if unreachable)
On Error Resume Next
Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")
If Err.Number <> 0 Then
    WScript.Echo "[ERROR] WMI connection failed: " & Err.Description
    WScript.Quit 1
End If
On Error GoTo 0

' Get Operating System information
Set colOS = objWMIService.ExecQuery("SELECT * FROM Win32_OperatingSystem")
For Each objOS In colOS
    os_name = objOS.Caption
    os_version = objOS.Version
Next

' Get Computer information
Set colComputer = objWMIService.ExecQuery("SELECT * FROM Win32_ComputerSystem")
For Each objComputer In colComputer
    computer_name = objComputer.Name
Next
Set objNetwork = CreateObject("WScript.Network")
current_user = objNetwork.UserName

' Get CPU information
Set colCPU = objWMIService.ExecQuery("SELECT * FROM Win32_Processor")
For Each objCPU In colCPU
    cpu_name = objCPU.Name
    cpu_cores = objCPU.NumberOfCores
Next

' Get Memory information
Set colMemory = objWMIService.ExecQuery("SELECT * FROM Win32_PhysicalMemory")
total_ram = 0
For Each objMemory In colMemory
    total_ram = total_ram + objMemory.Capacity
Next
total_ram = FormatNumber(total_ram / 1024 ^ 3, 2)

' Get Network Adapter information
Set colNetworkAdapters = objWMIService.ExecQuery("SELECT * FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled=True")
network_adapters = ""
For Each objNetworkAdapter In colNetworkAdapters
    network_adapters = network_adapters & "Adapter: " & objNetworkAdapter.Description & vbCrLf
    network_adapters = network_adapters & "IP: " & objNetworkAdapter.IPAddress(0) & vbCrLf
    network_adapters = network_adapters & "MAC: " & objNetworkAdapter.MACAddress & vbCrLf & vbCrLf
Next

' Get Serial Number
Set colBIOS = objWMIService.ExecQuery("SELECT * FROM Win32_BIOS")
For Each objBIOS In colBIOS
    serial_number = objBIOS.SerialNumber
Next

' Build the formatted report
report = "=== Workstation Information ===" & vbCrLf & vbCrLf & _
    "=== Operating System ===" & vbCrLf & _
    "Name: " & os_name & vbCrLf & _
    "Version: " & os_version & vbCrLf & vbCrLf & _
    "=== Computer ===" & vbCrLf & _
    "Name: " & computer_name & vbCrLf & _
    "User: " & current_user & vbCrLf & _
    "Serial: " & serial_number & vbCrLf & vbCrLf & _
    "=== Hardware ===" & vbCrLf & _
    "CPU: " & cpu_name & vbCrLf & _
    "Cores: " & cpu_cores & vbCrLf & _
    "RAM: " & total_ram & " GB" & vbCrLf & vbCrLf & _
    "=== Network ===" & vbCrLf & _
    network_adapters

' Render: popup under wscript, stdout under cscript
If LCase(Right(WScript.FullName, 11)) = "wscript.exe" Then
    MsgBox report, vbInformation + vbOKOnly, "Workstation Information"
Else
    WScript.Echo report
End If

WScript.Quit 0
