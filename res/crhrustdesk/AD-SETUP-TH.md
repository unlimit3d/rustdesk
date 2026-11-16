# เปิดใช้บัญชี AD และเลือกผู้รีโมตผ่าน Management

สถานะ: เตรียม source, patch และ config แล้ว ยังไม่ build API/client/ตัวติดตั้ง และยังไม่ได้ทดลอง Login กับ AD จริง ห้ามเปิด LDAP ด้วย binary เดิมก่อนใช้ strict-auth patch

Domain คือ `crhdomain.local` ตรวจ DNS จาก `172.16.1.10` พบ `adserver.crhdomain.local` ที่ `172.16.1.10` และ `adserver-02.crhdomain.local` ที่ `172.16.1.20` ตรวจ TCP636 ของเครื่องแรกเข้าถึงได้ แต่ยังไม่ยืนยัน certificate chain หรือรหัสผ่าน AD

การตั้งค่าล่าสุดตามผู้ใช้: ใช้ LDAP ปกติ `ldap://172.16.1.10:389` และบัญชี service `LDAP_READER@crhdomain.local` แทน LDAPS การเชื่อมต่อส่วนนี้ไม่มี TLS จึงไม่ต้องใช้ CA สำหรับ LDAP แต่รหัสผ่าน AD จะผ่านเครือข่ายโดยไม่มี TLS ป้องกัน ส่วน HTTPS ของ CrhRustDesk client ยังคงต้องใช้ certificate ตามเดิม ชุด Ubuntu จัดไว้ใน `ubuntu/` และยังไม่ build หรือเริ่มบริการ

## เตรียม AD บนเซิร์ฟเวอร์บัญชี

1. ใช้เครื่องที่รองรับบริการชุดปัจจุบัน Windows Server 2022 ขึ้นไปหรือ Linux ที่เตรียม deployment แล้ว Windows Server 2012 R2 ใช้ binary API/Caddy ปัจจุบันโดยตรงไม่ได้
2. ใช้บัญชี service `LDAP_READER@crhdomain.local` ที่อ่าน directory ได้ โดยไม่ใช้ Domain Admin เก็บ bind password บน server เท่านั้น ไม่ใส่ใน client หรือตัวติดตั้ง
3. อนุญาตการเชื่อมต่อจาก server CrhRustDesk ไปยัง `172.16.1.10` TCP389 ตามตัวเลือก LDAP ปกติของผู้ใช้ ถ้า AD ปฏิเสธ simple bind ตามนโยบาย ให้แจ้งผู้ดูแล AD ไม่เปลี่ยนนโยบาย signing อัตโนมัติ หากกลับไปใช้ LDAPS ให้ตั้ง URL/CA ตาม [แนวทาง Microsoft](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/enable-ldap-over-ssl-3rd-certification-authority)
4. ใช้ patch `patches/rustdesk-api-ad-strict.patch` กับ source `lejianwen/rustdesk-api` ก่อน build เมื่อผู้ใช้สั่ง build แล้วเท่านั้น Patch ทำให้ AD ล้มเหลวแล้วไม่ fallback ไปใช้ local password สำหรับชื่อเดียวกัน และตรวจสถานะ AD ซ้ำเมื่อใช้ token บัญชี `admin` ถูกสงวนเป็น local สำหรับกู้ระบบ
5. รวมส่วน `ldap` จาก `ad-config.example.yaml` ลงใน config ที่ API ใช้จริง เปลี่ยน `bind-dn` ให้ตรงกับบัญชี service และใช้ secret `RUSTDESK_API_LDAP_BIND_PASSWORD` จาก environment ของบริการ ไม่เก็บรหัสไว้ในตัวอย่าง yaml คง `tls-verify: true`
6. คง `admin-group` และ `allow-group` เป็นค่าว่าง ไม่ต้องสร้างกลุ่ม IT เพื่อกำหนดสิทธิ์รีโมต ผู้ดูแลเลือก username รายคนใน Management แทน บัญชี AD สามารถยืนยันตัวตนกับ API ได้ แต่ยังไม่ได้รับสิทธิ์รีโมตจนกว่าจะถูกเลือก
7. ก่อนเปิด AD ให้เพิกถอน token เดิมของบัญชีที่เปลี่ยนจาก local เป็น AD และทดสอบด้วยบัญชีทั่วไป บัญชี `admin` local ยังคงใช้รหัสเดิม ไม่ใช่รหัส AD ตั้งอายุ JWT สั้นตามนโยบาย และรักษา JWT secret ให้ตรงกับ hbbs

อย่าใช้ Start-DevServer.ps1 เพื่อเริ่ม production API ที่ปรับ LDAP แล้ว สคริปต์ dev เขียน config ใหม่จาก template ต้องแยก service launcher/config ของ production เพื่อรักษาค่า AD และ secret ที่ตั้งไว้

## เลือก username และสิทธิ์

เมื่อเปิดใช้บริการ Management รุ่นใหม่แล้ว เปิด `http://127.0.0.1:21120/_admin/` บนเครื่อง server หรือผ่านช่องทางที่ผู้ดูแลอนุญาต หน้า Management นี้ยังไม่ถูกเปิดใช้ในบริการที่กำลังรันจาก source รุ่นก่อน

1. Login ด้วยบัญชีผู้ดูแล CrhRustDesk เช่น `admin` local
2. ค้นหา username ที่เคย Login แล้ว หรือพิมพ์ชื่อ AD ในช่อง Username โดยตรง เช่น `somchai` ใช้ `sAMAccountName` ไม่ต้องใส่ `CRHDOMAIN\` และไม่ต้องกรอกรหัสของผู้ใช้
3. เลือกอนุญาตรีโมตโดยแจ้งเตือนปลายทาง แล้วเลือกทุกเครื่อง หรือกรอก ID เครื่องที่อนุญาตคั่นด้วย comma
4. กดบันทึกสิทธิ์ ผู้ใช้ Login ใน CrhRustDesk ด้วย username/password AD ของตนเองได้เมื่อระบบ AD พร้อมแล้ว การเพิ่มชื่อใน Management ไม่สร้างบัญชี AD และไม่เปลี่ยนรหัสผ่าน AD
5. เมื่อต้องการถอนสิทธิ์ ให้เอาเครื่องหมายอนุญาตออกแล้วบันทึก เครื่องปลายทางรุ่นใหม่ที่ติดตั้งโหมดรับเข้าอย่างเดียวจะปฏิเสธผู้ที่ไม่มีใบอนุญาตส่วนกลาง ไม่เปิดช่องให้ขอกดยอมรับแทน

บัญชีที่มี role administrator ยังได้สิทธิ์ตาม `allow_admin` ใน policy เดิม หน้า Management แสดงข้อยกเว้นนี้ และไม่ได้ให้สิทธิ์ administrator กับผู้ใช้ AD อัตโนมัติ การตั้งค่าสิทธิ์ผ่าน UI ตรวจ role จาก API ทุกคำขอ Token เก็บในหน่วยความจำของหน้าเว็บ ไม่เก็บใน localStorage

ตัวอย่าง `somchai` มีสิทธิ์เฉพาะเครื่อง `262799361`: ตั้ง Username เป็น `somchai`, เลือกอนุญาต, ไม่เลือกทุกเครื่อง, ใส่ `262799361` แล้วบันทึก ส่วน `AD_USERNAME` local เดิมจะไม่สามารถ Login ด้วยรหัส local หลังเปิด strict AD เว้นแต่มีบัญชีชื่อเดียวกันใน AD และใช้รหัส AD ที่ถูกต้อง

การถอนสิทธิ์หยุดการออก permit ใหม่ทันที ใบเดิมหมดอายุไม่เกิน 60 วินาที การปิดบัญชี AD ทำให้คำขอยืนยันตัวตนใหม่ถูกปฏิเสธเมื่อใช้ API ที่ patch แล้ว แต่ session ที่เปิดอยู่ต้องตัดจากเครื่องปลายทาง สิทธิ์ปัจจุบันครอบคลุม desktop แบบแจ้งเตือนปลายทาง ยังไม่ออก permit สำหรับ terminal, tunnel, camera หรือหน้าต่าง file-transfer แยก

Management ฟังเฉพาะ loopback พอร์ต21120 และ Caddy config รุ่นใหม่บล็อก `/crhrustdesk/admin/*` จาก LAN ต้องใช้ Caddy config รุ่นใหม่ก่อนเปิด Management ไม่เปิด HTTP admin ให้ผู้ใช้ทั่วไป หากต้องการบริหารจากเครื่อง IT ให้จัดช่องทาง HTTPS หรือ tunnel พร้อมนโยบายขององค์กรก่อน
