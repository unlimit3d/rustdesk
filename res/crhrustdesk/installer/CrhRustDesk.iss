#ifndef BundleRoot
  #error Build this installer with Build-EasySetup.ps1
#endif

[Setup]
AppId=CrhRustDesk.EasySetup
AppName=CrhRustDesk
AppVersion={#AppVersion}
AppVerName=CrhRustDesk {#AppVersion}
DefaultDirName={autopf}\CrhRustDesk
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
DisableWelcomePage=no
DisableDirPage=yes
DisableProgramGroupPage=yes
WizardStyle=modern
SetupMutex=CrhRustDesk.EasySetup
SetupLogging=yes
SetupIconFile={#BundleRoot}\CrhRustDesk.ico
Compression=lzma2/normal
SolidCompression=yes
OutputBaseFilename=CrhRustDesk-Setup
VersionInfoDescription=CrhRustDesk client installer

[Files]
Source: "{#BundleRoot}\*"; DestDir: "{tmp}\CrhRustDeskPayload"; Excludes: "build-scripts\*,*.patch,SOURCE-COMMIT.txt,build-provenance.json,Install.ps1,LAN-SETUP-TH.md,*.sha256"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
Filename: "{code:LaunchExe}"; Description: "Open CrhRustDesk"; Flags: postinstall nowait skipifsilent runasoriginaluser

[Code]
var
  TrustPage: TInputOptionWizardPage;
  RolePage: TInputOptionWizardPage;
  AutoUpdate: Boolean;

function InstalledAppName: String;
begin
  if RolePage.SelectedValueIndex = 1 then Result := 'CrhRustDeskIT'
  else Result := 'CrhRustDesk';
end;

function InstalledDirectory: String;
begin
  Result := ExpandConstant('{autopf}') + '\' + InstalledAppName;
end;

function InstalledExe: String;
begin
  Result := InstalledDirectory + '\' + InstalledAppName + '.exe';
end;

function LaunchExe(Param: String): String;
begin
  Result := InstalledExe;
end;

procedure PrepareManagedUpdate;
var
  Profile: AnsiString;
  Expected: String;
begin
  if not WizardSilent then RaiseException('Managed updates require silent mode');
  RolePage.SelectedValueIndex := 0;
  if not LoadStringFromFile(ExpandConstant('{autopf}\CrhRustDesk\connection-profile.json'), Profile) then
    RaiseException('Managed updates require an existing installation');
  Expected := ',"id_server":"{#IdServer}","relay_server":"{#RelayServer}","api_server":"{#ApiServer}","key":"{#ServerKey}"}';
  if String(Profile) = '{"role":"incoming"' + Expected then RolePage.SelectedValueIndex := 0
  else RaiseException('Installation role or server configuration differs; use interactive setup');
  if CompareText(GetSHA256OfFile(ExpandConstant('{autopf}\CrhRustDesk\CrhRustDesk-dev-root.crt')), '{#CertificateHash}') <> 0 then
    RaiseException('CA changed; use interactive setup');
  if CompareText(GetSHA256OfFile(ExpandConstant('{autopf}\CrhRustDesk\update-public-key.xml')), '{#UpdateKeyHash}') <> 0 then
    RaiseException('Update trust key changed; use interactive setup');
  TrustPage.Values[0] := True;
end;

procedure InitializeWizard;
var
  ExistingProfile: AnsiString;
begin
  RolePage := CreateInputOptionPage(wpWelcome,
    'เลือกการใช้งานเครื่องนี้', 'เลือกบทบาทของเครื่องที่จะติดตั้ง',
    'ติดตั้งแยกโปรแกรม: CrhRustDesk รับรีโมตเข้า ส่วน CrhRustDeskIT ใช้ Login และรีโมตออก หากต้องการทั้งสองแบบในเครื่องเดียว ให้รัน Setup สองครั้งแล้วเลือกคนละบทบาท',
    True, False);
  RolePage.Add('เครื่องปลายทาง — รับการรีโมตเข้าเท่านั้น');
  RolePage.Add('เครื่อง IT — รีโมตออกไปยังเครื่องอื่นเท่านั้น');
  RolePage.SelectedValueIndex := 0;
  if FileExists(ExpandConstant('{autopf}\CrhRustDeskIT\CrhRustDeskIT.exe')) then
    RolePage.SelectedValueIndex := 1;
  if LoadStringFromFile(ExpandConstant('{autopf}\CrhRustDesk\connection-profile.json'), ExistingProfile) then
    if Pos('{"role":"outgoing",', String(ExistingProfile)) = 1 then
      RolePage.SelectedValueIndex := 1;
  if ExpandConstant('{param:ROLE|}') = 'outgoing' then RolePage.SelectedValueIndex := 1;
  if ExpandConstant('{param:ROLE|}') = 'incoming' then RolePage.SelectedValueIndex := 0;
  TrustPage := CreateInputOptionPage(RolePage.ID,
    'ตั้งค่าเซิร์ฟเวอร์ CrhRustDesk',
    'ติดตั้งและตั้งค่าอัตโนมัติ โดยไม่ต้องพิมพ์คำสั่ง',
    'Server: {#IdServer}' + #13#10 +
    'Account API: {#ApiServer}' + #13#10#13#10 +
    'ชุดนี้จะเพิ่ม CA ภายในของเซิร์ฟเวอร์ลง Trusted Root ทั้งเครื่อง ทำให้เชื่อถือ certificate ทุกใบที่ CA นี้ออก' + #13#10 +
    'Certificate SHA-256:' + #13#10 +
    '{#Copy(CertificateHash, 1, 32)}' + #13#10 +
    '{#Copy(CertificateHash, 33, 32)}' + #13#10#13#10 +
    'ไม่มีการฝังรหัสผ่าน และไม่ปิด Firewall หรือการป้องกันของ Windows',
    False, False);
  TrustPage.Add('ยอมรับ CA ภายในของเซิร์ฟเวอร์ CrhRustDesk นี้');
  TrustPage.Values[0] := not WizardSilent;
  AutoUpdate := ExpandConstant('{param:CRHUPDATE|0}') = '1';
  if AutoUpdate then PrepareManagedUpdate;
  WizardForm.FinishedLabel.Caption :=
    'ติดตั้ง CrhRustDesk และตั้งค่า server แล้ว' + #13#10#13#10 +
    'Login บัญชีส่วนกลางบนเครื่องควบคุม แล้วเชื่อมต่อด้วย ID หรือ IP ของเครื่องปลายทาง' + #13#10 +
    'บัญชีที่ได้รับสิทธิ์จาก server เข้าได้โดยแจ้งเตือนปลายทาง บัญชีที่ไม่ได้รับสิทธิ์จะถูกปฏิเสธ';
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = TrustPage.ID) and not TrustPage.Values[0] then begin
    MsgBox('ต้องยอมรับ CA ภายในก่อนติดตั้ง หากไม่ต้องการเชื่อถือ CA นี้ ให้กดยกเลิก', mbInformation, MB_OK);
    Result := False;
  end;
end;

procedure RunChecked(const FileName, Params: String);
var
  ResultCode: Integer;
begin
  if not Exec(FileName, Params, ExtractFileDir(FileName), SW_HIDE,
      ewWaitUntilTerminated, ResultCode) then
    RaiseException('เริ่มคำสั่งติดตั้งไม่ได้: ' + SysErrorMessage(ResultCode));
  if ResultCode <> 0 then
    RaiseException('คำสั่งติดตั้งไม่สำเร็จ รหัสข้อผิดพลาด: ' + IntToStr(ResultCode));
end;

procedure VerifyOption(const Name, Value: String);
var
  ResultCode, I: Integer;
  Output: TExecOutput;
begin
  if not ExecAndCaptureOutput(InstalledExe, '--option ' + Name, '',
      SW_HIDE, ewWaitUntilTerminated, ResultCode, Output) then
    RaiseException('อ่านค่าติดตั้งกลับไม่ได้: ' + Name);
  if (ResultCode <> 0) or Output.Error then
    RaiseException('ตรวจค่าติดตั้งไม่สำเร็จ: ' + Name);
  for I := 0 to GetArrayLength(Output.StdOut) - 1 do
    if Trim(Output.StdOut[I]) = Value then Exit;
  RaiseException('ค่า profile ที่โปรแกรมอ่านไม่ตรงกับชุดติดตั้ง: ' + Name);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  PayloadExe, CertificateFile, Role, Profile, PayloadDirectory: String;
begin
  if CurStep = ssInstall then begin
    if not TrustPage.Values[0] then
      RaiseException('ต้องติดตั้งแบบโต้ตอบและยอมรับ CA ก่อน ไม่รองรับ silent install ในชุดนี้');
  end;
  if CurStep = ssPostInstall then begin
    PayloadExe := ExpandConstant('{tmp}\CrhRustDeskPayload\CrhRustDesk.exe');
    PayloadDirectory := ExpandConstant('{tmp}\CrhRustDeskPayload');
    if RolePage.SelectedValueIndex = 1 then begin
      PayloadExe := PayloadDirectory + '\CrhRustDeskIT.exe';
      if not RenameFile(PayloadDirectory + '\CrhRustDesk.exe', PayloadExe) then
        RaiseException('Cannot prepare the separate IT executable');
    end;
    CertificateFile := ExpandConstant('{tmp}\CrhRustDeskPayload\CrhRustDesk-dev-root.crt');
    if CompareText(GetSHA256OfFile(CertificateFile), '{#CertificateHash}') <> 0 then
      RaiseException('Certificate ไม่ตรงกับชุดติดตั้ง');

    WizardForm.StatusLabel.Caption := 'เพิ่ม certificate ของเซิร์ฟเวอร์...';
    if not AutoUpdate then
      RunChecked(ExpandConstant('{sys}\certutil.exe'),
        '-addstore -f Root "' + CertificateFile + '"');

    WizardForm.StatusLabel.Caption := 'ติดตั้ง CrhRustDesk และบริการ Windows...';
    if RolePage.SelectedValueIndex = 0 then Role := 'incoming' else Role := 'outgoing';
    Profile := '{"role":"' + Role + '","id_server":"{#IdServer}","relay_server":"{#RelayServer}","api_server":"{#ApiServer}","key":"{#ServerKey}"}';
    if not SaveStringToFile(ExpandConstant('{tmp}\CrhRustDeskPayload\connection-profile.json'), Profile, False) then
      RaiseException('บันทึกบทบาทเครื่องไม่ได้');
    if AutoUpdate then RunChecked(PayloadExe, '--update')
    else RunChecked(PayloadExe, '--silent-install');
    if not FileExists(InstalledExe) then
      RaiseException('ไม่พบแอปหลังติดตั้ง กรุณาตรวจ Setup log');
    if CompareText(GetSHA256OfFile(InstalledDirectory + '\connection-profile.json'),
        GetSHA256OfFile(ExpandConstant('{tmp}\CrhRustDeskPayload\connection-profile.json'))) <> 0 then
      RaiseException('บทบาทเครื่องที่ติดตั้งไม่ตรงกับที่เลือก กรุณาตรวจ Setup log');
    if CompareText(GetSHA256OfFile(InstalledExe), GetSHA256OfFile(PayloadExe)) <> 0 then
      RaiseException('ไฟล์แอปที่ติดตั้งไม่ตรงกับชุดนี้ กรุณาตรวจ Setup log');
    if CompareText(GetSHA256OfFile(InstalledDirectory + '\librustdesk.dll'),
        GetSHA256OfFile(ExpandConstant('{tmp}\CrhRustDeskPayload\librustdesk.dll'))) <> 0 then
      RaiseException('Rust DLL ที่ติดตั้งไม่ตรงกับชุดนี้ กรุณาตรวจ Setup log');

    VerifyOption('custom-rendezvous-server', '{#IdServer}');
    VerifyOption('relay-server', '{#RelayServer}');
    VerifyOption('api-server', '{#ApiServer}');
    VerifyOption('key', '{#ServerKey}');
    if Role = 'incoming' then VerifyOption('direct-server', 'Y')
    else VerifyOption('direct-server', 'N');
    if Role = 'incoming' then
      WizardForm.FinishedLabel.Caption := 'ติดตั้งเครื่องปลายทางแล้ว รอให้สถานะ Ready แล้วแจ้ง ID หรือ IP ให้ IT บัญชีที่ได้รับสิทธิ์ใน Management เข้าได้โดยแจ้งเตือนปลายทาง'
    else
      WizardForm.FinishedLabel.Caption := 'ติดตั้ง CrhRustDeskIT แยกแล้ว Login ด้วยบัญชีที่ได้รับสิทธิ์ แล้วใส่ ID หรือ IP ของเครื่องปลายทาง หากต้องการรับรีโมตเข้าในเครื่องนี้ ให้รัน Setup อีกครั้งแล้วเลือกเครื่องปลายทาง';
    if not AutoUpdate then
      RunChecked(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
        '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + InstalledDirectory + '\updater\Register-AutoUpdate.ps1"');
    if AutoUpdate then
      RunChecked(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
        '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + InstalledDirectory + '\updater\Register-AutoUpdate.ps1" -ScheduleOnly');
    if AutoUpdate then Exit;
    WizardForm.StatusLabel.Caption := 'ตั้งค่า Firewall สำหรับเครื่องควบคุม...';
    if Role = 'incoming' then
      RunChecked(ExpandConstant('{sys}\netsh.exe'),
        'advfirewall firewall set rule name="CrhRustDesk Service" dir=in new enable=yes profile=domain,private remoteip={#ControllerAddress}')
    else
      RunChecked(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
        '-NoProfile -NonInteractive -Command "Get-NetFirewallRule -ErrorAction Stop | Where-Object { $_.DisplayName -eq ''CrhRustDeskIT Service'' } | Disable-NetFirewallRule -ErrorAction Stop"');
  end;
end;
