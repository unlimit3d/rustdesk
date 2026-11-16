# ติดตั้ง CrhRustDesk บน Windows

ชุด Ubuntu ที่เลือกบทบาทเครื่องและใช้ Management/AD build แล้วใน `target/CrhRustDesk-Ubuntu-Setup` ใช้ [คู่มือติดตั้งสำหรับ Ubuntu](INSTALL-UBUNTU-TH.md) สำหรับชุดนี้ ส่วนคำแนะนำด้านล่างอ้างอิงชุด dev เดิม

ใช้ `CrhRustDesk-Setup.exe` สำหรับติดตั้งหรืออัปเดต CrhRustDesk บน Windows 10/11 x64 ชุดนี้เชื่อมต่อเซิร์ฟเวอร์ dev `172.29.0.96` ผ่าน HTTPS `https://172.29.0.96:8443` เครื่อง dev ต้องเปิดอยู่และปลายทางต้องเข้าถึง LAN นี้ได้

1. คัดลอก `CrhRustDesk-Setup.exe` ไปยังเครื่องปลายทาง เช่น `172.29.0.52`
2. ดับเบิลคลิกไฟล์ แล้วกด **Yes** เมื่อ Windows ขอสิทธิ์ Administrator หากใช้บัญชีทั่วไป ให้ผู้ดูแลกรอกบัญชี Administrator
3. กด **Next** ตรวจ IP ของ server และ SHA-256 ของ CA แล้วเลือกยอมรับ CA ของ dev เมื่อต้องการเชื่อถือ CA นี้ทั้งเครื่อง จากนั้นกด **Next → Install**
4. เมื่อเสร็จ กด **Finish** เพื่อเปิด CrhRustDesk แล้วแจ้ง ID ของเครื่องปลายทางให้ผู้ควบคุม

อัปเดตทั้งเครื่องควบคุมและเครื่องปลายทางเป็นรุ่นนี้ ปิดตัว portable เก่าก่อน แล้วเปิด CrhRustDesk จาก Desktop หรือ Start Menu

บนเครื่องควบคุม Login ด้วยบัญชีส่วนกลาง แล้วใส่ ID หรือ `172.29.0.52` เพื่อเชื่อมต่อ บัญชี admin ที่เซิร์ฟเวอร์ยืนยัน role และบัญชี `AD_USERNAME` ที่ได้รับสิทธิ์ส่วนกลาง เข้า desktop ได้โดยไม่ต้องกดยอมรับ ปลายทางแสดง connection manager พร้อมชื่อบัญชี และหยุด session ได้ บัญชีอื่นยังต้องขออนุมัติ หากปลายทางตั้ง 2FA ไว้ ยังต้องผ่าน 2FA ตามเดิม ไม่มี username/password ฝังในตัวติดตั้ง

การพิมพ์ IP ใช้ TCP `21118` บนเครื่องปลายทาง ตรวจ public key กับเซิร์ฟเวอร์ก่อนเข้ารหัส จึงต้อง Login และให้เครื่องปลายทางลงทะเบียนกับ server แล้ว ไม่มีการถอยไปใช้ Direct IP แบบไม่เข้ารหัส ตัวติดตั้งจำกัด inbound rule ของ CrhRustDesk ให้ Domain หรือ Private profile และเครื่องควบคุม `172.29.0.96` หากใช้อีกเครื่องเป็นตัวควบคุม ให้ผู้ดูแลปรับขอบเขต rule ให้ตรงกับ IP นั้น

หน้าแอปและเมนู tray แสดง IPv4 ของ adapter ที่ใช้งานอยู่ หากมีหลาย adapter จะแสดงหลาย IP ให้เลือก IP ที่อยู่ใน LAN เดียวกับเครื่องควบคุม

ตรวจ SHA-256 ของ CA เทียบกับค่าที่ผู้ดูแลส่งให้ผ่านช่องทางที่เชื่อถือได้:

```text
07E9C24461C85909EB555EC6EA9CA5F2D82EABA59EAC237F0BE0B335F20992D8
```

หากติดตั้งไม่สำเร็จ ให้เก็บข้อความผิดพลาดและไฟล์ `Setup Log*.txt` ใน `%TEMP%` ส่งให้ผู้ดูแล การติดตั้งบางส่วน รวมถึง CA ที่เพิ่มสำเร็จแล้ว อาจยังอยู่ ตัวติดตั้งไม่ได้ย้อนกลับการเปลี่ยนแปลงของ native installer หรือ trust store โดยอัตโนมัติ หากนโยบายองค์กรห้ามเพิ่ม CA ให้ผู้ดูแลจัดการ certificate ตามนโยบายก่อน

ถอนแอปได้ที่ **Settings → Apps → CrhRustDesk → Uninstall** การถอนแอปไม่ลบ CA ของ dev ให้ผู้ดูแลลบ CA ใบที่ตรงกันจาก **Certificates (Local Computer) → Trusted Root Certification Authorities** เมื่อเลิกใช้ และตรวจว่าไม่มีบริการอื่นใช้งาน CA นี้อยู่

ตัวติดตั้งยังไม่ได้ลงลายเซ็นดิจิทัล และยังไม่ได้ทดสอบติดตั้งหรือเปิด session จริงบน `172.29.0.52` ชุดนี้ใช้สำหรับทดลอง ไม่ใช่ผลรับรองว่าผ่าน security ขององค์กร ดูการตั้งค่า Firewall ใน [LAN-SETUP-TH.md](LAN-SETUP-TH.md)

ตัวติดตั้งสร้างด้วย [Inno Setup](https://jrsoftware.org/inno-setup) ตาม license ที่แนบใน `INNO-LICENSE.txt` ส่วน source ของตัวติดตั้งอยู่ใน `installer/CrhRustDesk.iss` และ `Build-EasySetup.ps1` การแจกจ่าย client ต้องคง license และจัดให้มี corresponding source ตามเงื่อนไข AGPL ของโครงการ
