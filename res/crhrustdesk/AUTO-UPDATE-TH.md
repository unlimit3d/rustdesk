# อัปเดต CrhRustDesk ผ่านเซิร์ฟเวอร์ภายใน

สถานะ: เพิ่ม source แล้ว แต่ยังไม่ได้ build client หรือตัวติดตั้งที่มีฟีเจอร์นี้ ยังไม่ได้ติดตั้ง Scheduled Task บนเครื่อง dev หรือเครื่องผู้ใช้ และยังไม่มี release ที่เผยแพร่ให้ติดตั้งอัตโนมัติ ตัวติดตั้งเดิมยังไม่มีระบบนี้

## การทำงาน

ติดตั้ง client รุ่นที่มีระบบอัปเดตครั้งแรกด้วย Setup แบบโต้ตอบ เลือกบทบาทและยอมรับ CA ตามเดิม Setup จะเพิ่ม Scheduled Task ชื่อ `CrhRustDesk AutoUpdate` ซึ่งทำงานด้วย SYSTEM ตอนเปิดเครื่องและทุกวันเวลา 03:00 น. ตามเวลาของเครื่องนั้น

Task ตรวจ `https://172.16.1.83:8443/crhrustdesk/updates/latest.json` หากยังไม่เผยแพร่ release จะไม่ติดตั้งอะไร เมื่อมีรุ่นใหม่ Task ตรวจลายเซ็น RSA-3072 ของรายการรุ่น URL จาก server เดิม ขนาดไฟล์ SHA-256 และ revision ที่สูงกว่ารุ่นติดตั้งแล้ว ก่อนดาวน์โหลดและติดตั้ง

เครื่องปลายทางตรวจ session ผ่าน IPC ที่มีอยู่ของแอป หากมี session หรือยืนยันสถานะไม่ได้จะเลื่อนไปตรวจครั้งถัดไป เครื่อง IT บทบาท outgoing จะรอจนปิดแอป CrhRustDesk ทั้งหมด เพราะไม่มี receiving service สำหรับยืนยันสถานะ เมื่อดาวน์โหลดเสร็จจะตรวจสถานะอีกครั้งก่อนติดตั้ง การตรวจนี้ไม่ใช่การล็อกห้ามเริ่ม session ใหม่ระหว่างขั้นตอนติดตั้ง

การอัปเดตใช้บทบาทและ server เดิม คง CA และ update public key เดิม และใช้ native `--update` เพื่อคงการตั้งค่าที่ติดตั้งไว้ หากเปลี่ยน CA, server หรือ update trust key ต้องติดตั้งแบบโต้ตอบอีกครั้ง การเปลี่ยนรหัส Windows หรือ AD ไม่เกี่ยวกับ Scheduled Task นี้

ไฟล์ใน `%ProgramData%\CrhRustDesk-Updater` จำกัดให้ SYSTEM และ Administrators เขียนได้ Task บันทึก revision ที่ใช้สำเร็จหลังตรวจ DLL ที่ติดตั้งตรงกับรายการรุ่นแล้ว การตรวจล้มเหลวจะไม่ยืนยัน revision ใหม่

## กุญแจสำหรับเผยแพร่

กุญแจชุดแรกสร้างไว้บนเครื่อง dev ที่ `D:\Project\2569\CrhRustDesk-build-tools\update-signing` โดยจำกัดสิทธิ์ directory แล้ว:

* `update-private-key.xml` ใช้ลงนาม เก็บเฉพาะเครื่องเผยแพร่และสำรองแบบเข้ารหัส อย่าอัปโหลดเข้า Ubuntu หรือใส่ในชุด client
* `update-public-key.xml` ใส่ใน client เพื่อยืนยันรายการรุ่น

ถ้าย้ายเครื่องเผยแพร่ ให้ย้ายกุญแจเดิมผ่านช่องทางส่วนตัว หากทำกุญแจหายจะต้องติดตั้ง public key ใหม่บน client แบบโต้ตอบ ไม่สร้างกุญแจใหม่ทับชุดเดิม

## เตรียม client รุ่นแรก

เมื่อสั่ง build ให้ใช้ `Build.ps1` โดยระบุ server, transport public key, permit public key และ CA ของ Ubuntu เช่นเดียวกับชุดเดิม Script ใช้ update public key จาก `ToolsRoot\update-signing\update-public-key.xml` หรือรับ path ผ่าน `-UpdatePublicKey`

จากนั้น `Build-EasySetup.ps1` เพิ่ม `client-release.json` และฝังเลข revision โดยค่าเริ่มต้นมาจากเวลา UTC สามารถระบุ `-ReleaseRevision` เองได้ แต่ต้องสูงกว่าทุกรุ่นที่เคยเผยแพร่ เลข version ที่หน้าจออาจเท่ากันได้ แต่ revision ของแต่ละชุดต้องเพิ่มขึ้น

ต้องนำ Setup รุ่นแรกนี้ไปติดตั้งที่เครื่อง IT และปลายทางด้วยสิทธิ์ Administrator ก่อน เครื่องที่ใช้ Setup เดิมยังตรวจอัปเดตเองไม่ได้

## ลงนามและเผยแพร่รุ่นถัดไป

1. ใช้ bundle ใหม่ที่มี `client-release.json`, update public key และโฟลเดอร์ `updater` พร้อม Setup ที่สร้างจาก bundle เดียวกัน อย่าใช้ bundle หรือ Setup เดิมที่ยังไม่มี managed updater
2. บนเครื่อง dev รันสคริปต์ต่อไปนี้ โดยแทน path ของ bundle และ Setup ด้วยชุดที่เพิ่ง build:

```powershell
.\res\crhrustdesk\Publish-ClientUpdate.ps1 `
  -BundlePath 'D:\Project\2569\rustdesk\target\BUNDLE-ใหม่' `
  -SetupPath 'D:\Project\2569\rustdesk\target\SETUP-ใหม่\CrhRustDesk-Setup.exe' `
  -PrivateKeyPath 'D:\Project\2569\CrhRustDesk-build-tools\update-signing\update-private-key.xml' `
  -OutputDirectory 'D:\Project\2569\CrhRustDesk-build-tools\update-release' `
  -ApiServer 'https://172.16.1.83:8443'
```

3. อัปโหลดเฉพาะ `latest.json` และ directory `releases` ที่ได้ ไปยัง directory staging ส่วนตัวบน Ubuntu ไม่อัปโหลด private key
4. บน Ubuntu ใช้คำสั่งนี้เพื่อคัดลอกไฟล์ ตรวจขนาด/hash และสลับรายการรุ่นล่าสุดหลังคัดลอกเสร็จ:

```bash
sudo python3 -B /home/SSH_USER/crhrustdesk-staging/ubuntu/install-update-release.py /home/SSH_USER/update-release
```

เครื่อง client เป็นผู้ตรวจลายเซ็น RSA ก่อนติดตั้ง สคริปต์คัดลอกบน Ubuntu ตรวจ metadata และ hash แต่ไม่ได้ยืนยันลายเซ็น RSA เอง จึงต้องเผยแพร่เฉพาะไฟล์ที่สร้างจากเครื่องลงนามที่เชื่อถือได้

รายการรุ่นมีอายุ 30 วัน หากหมดอายุ client จะปฏิเสธการอัปเดต ให้เตรียมรายการลงนามใหม่และ revision ใหม่ ไม่ข้ามการตรวจลายเซ็นหรือ certificate

## ตรวจและควบคุมการอัปเดต

หลังติดตั้งรุ่นที่รองรับแล้ว บน Windows Administrator PowerShell ตรวจหรือสั่งตรวจทันทีได้ด้วย:

```powershell
Get-ScheduledTask -TaskName 'CrhRustDesk AutoUpdate'
Start-ScheduledTask -TaskName 'CrhRustDesk AutoUpdate'
Get-ScheduledTaskInfo -TaskName 'CrhRustDesk AutoUpdate'
Get-Content "$env:ProgramData\CrhRustDesk-Updater\applied.json"
```

`LastTaskResult` เป็น 0 เมื่อคำสั่งจบตามปกติ รวมถึงยังไม่มีรุ่นใหม่หรือเลื่อนเพราะเครื่องไม่ว่าง ตรวจ revision ใน `applied.json` เพื่อยืนยันว่าติดตั้งรุ่นใหม่แล้ว

หยุดหรือนำ task ออกด้วยคำสั่งผู้ดูแลต่อไปนี้:

```powershell
Disable-ScheduledTask -TaskName 'CrhRustDesk AutoUpdate'
# หลังถอนแอป หาก task ยังอยู่:
Unregister-ScheduledTask -TaskName 'CrhRustDesk AutoUpdate' -Confirm:$false
```

Scheduled Task นี้เป็นช่องอัปเดตภายในที่แยกจากสวิตช์ update เดิมของ RustDesk ในแอป รุ่น CrhRustDesk ที่ติดตั้งแล้วจะไม่ใช้ native updater เดิมเพื่อแทนที่แอปด้วย release สาธารณะ

## การทดสอบที่ต้องผ่านก่อนใช้จริง

ตรวจ protocol ผ่านแล้วสำหรับลายเซ็นถูกต้อง revision ซ้ำ ลายเซ็นปลอม URL นอก server รายการหมดอายุ และขนาดเกินกำหนด โดยไม่ compile client

ยังต้อง build และทดสอบติดตั้งจริงสอง revision บน Windows ทั้ง incoming และ outgoing รวมถึงกรณีมี session อยู่ ส่งไฟล์ค้าง ดาวน์โหลดขาดหาย hash ไม่ตรง และการติดตั้งล้มเหลว ตรวจว่า ID บทบาท ค่า server กฎ Firewall และสิทธิ์รับ remote คงเดิมหลังอัปเดต ห้ามถือว่าการตรวจ protocol ผ่านแล้วเท่ากับระบบติดตั้งจริงผ่าน
