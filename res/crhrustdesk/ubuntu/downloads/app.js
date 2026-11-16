'use strict';

async function loadRelease() {
  const status = document.getElementById('release-status');
  const download = document.getElementById('download');
  const retry = document.getElementById('retry');
  retry.hidden = true;
  status.textContent = 'กำลังตรวจสอบเวอร์ชัน…';
  download.removeAttribute('href');
  download.setAttribute('aria-disabled', 'true');
  document.getElementById('verification').hidden = true;
  try {
    const response = await fetch('/crhrustdesk/updates/latest.json', {
      cache: 'no-store',
      credentials: 'omit',
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error('Release unavailable');
    const envelope = await response.json();
    const payload = Uint8Array.from(atob(envelope.payload), c => c.charCodeAt(0));
    const release = JSON.parse(new TextDecoder().decode(payload));
    const expectedUrl = `${location.origin}/crhrustdesk/updates/releases/${release.revision}/CrhRustDesk-Setup.exe`;
    if (release.schema !== 1 || release.product !== 'CrhRustDesk' ||
        release.platform !== 'windows-x64' || !Number.isSafeInteger(release.revision) ||
        release.revision <= 0 || !/^\d+\.\d+\.\d+(\.\d+)?$/.test(release.version) ||
        !/^[a-f0-9]{64}$/.test(release.sha256) ||
        !Number.isSafeInteger(release.size) || release.size <= 0 ||
        release.size > 536870912 || release.url !== expectedUrl) {
      throw new Error('Invalid release metadata');
    }
    status.textContent = `เวอร์ชัน ${release.version} · รุ่นเผยแพร่ ${release.revision}`;
    document.getElementById('file-size').textContent =
      `CrhRustDesk-Setup.exe · ${(release.size / 1048576).toFixed(1)} MB`;
    document.getElementById('sha256').textContent = release.sha256.toUpperCase();
    document.getElementById('verification').hidden = false;
    download.href = release.url;
    download.download = 'CrhRustDesk-Setup.exe';
    download.removeAttribute('aria-disabled');
  } catch (error) {
    status.textContent = 'ยังโหลดข้อมูลรุ่นล่าสุดไม่ได้ กรุณาตรวจการเชื่อมต่อแล้วลองอีกครั้ง';
    retry.hidden = false;
  }
}

document.getElementById('retry').addEventListener('click', loadRelease);
loadRelease();
