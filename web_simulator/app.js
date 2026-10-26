// State Management
const PERSISTENT_STORAGE_KEY = 'VAULT_DOCUMENTS_DIR_PERSISTENT'; // Simulates Android /storage/emulated/0/Documents/.calendar_vault/
const APP_LOCAL_STORAGE_KEY = 'CALENDAR_APP_LOCAL_DATA'; // Simulates /data/data/com.app/ (cleared on uninstall)
const ONBOARDING_KEY = 'HIDE_X_HAS_SEEN_GUIDE';
const ACTIVE_DISGUISE_KEY = 'HIDE_X_ACTIVE_DISGUISE';

let currentDate = new Date(2026, 9, 8); // October 2026
let selectedDate = new Date(2026, 9, 8);
let secretSequence = [7, 14, 21, 28];
let currentTappedBuffer = [];
let tapBufferTimeout = null;
let currentTab = 'all';
let activeViewerItem = null;

// Clock update
function updateClock() {
  const now = new Date();
  const hrs = String(now.getHours()).padStart(2, '0');
  const mins = String(now.getMinutes()).padStart(2, '0');
  const el = document.getElementById('clock-time');
  if (el) el.textContent = `${hrs}:${mins}`;
}
setInterval(updateClock, 1000);
updateClock();

// Load persistent vault storage (survives uninstall)
function getPersistentVaultData() {
  const raw = localStorage.getItem(PERSISTENT_STORAGE_KEY);
  if (!raw) {
    const defaultData = {
      items: [
        {
          id: 'sample-1',
          name: 'private_family_vacation.jpg',
          type: 'photo',
          size: 2450000,
          url: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=600&q=80',
          addedAt: new Date().toISOString()
        },
        {
          id: 'sample-2',
          name: 'tax_audit_report_2025.pdf',
          type: 'docs',
          size: 1120000,
          ext: 'pdf',
          addedAt: new Date().toISOString()
        },
        {
          id: 'sample-3',
          name: 'investment_portfolio.xlsx',
          type: 'docs',
          size: 980000,
          ext: 'xlsx',
          addedAt: new Date().toISOString()
        },
        {
          id: 'sample-4',
          name: 'encrypted_voice_memo.mp3',
          type: 'audio',
          size: 3400000,
          ext: 'mp3',
          addedAt: new Date().toISOString()
        }
      ],
      sequence: [7, 14, 21, 28]
    };
    savePersistentVaultData(defaultData);
    return defaultData;
  }
  try {
    return JSON.parse(raw);
  } catch (e) {
    return { items: [], sequence: [7, 14, 21, 28] };
  }
}

function savePersistentVaultData(data) {
  localStorage.setItem(PERSISTENT_STORAGE_KEY, JSON.stringify(data));
}

// App Local Storage (decoy events)
function getAppLocalData() {
  const raw = localStorage.getItem(APP_LOCAL_STORAGE_KEY);
  if (!raw) {
    return {
      events: [
        { id: 'ev1', title: 'Dentist Checkup', time: '10:30 AM', notes: 'Routine checkup', dateStr: '2026-10-08' },
        { id: 'ev2', title: 'Team Catchup', time: '03:00 PM', notes: 'Discuss project launch', dateStr: '2026-10-08' },
        { id: 'ev3', title: 'Grocery Run', time: '06:30 PM', notes: 'Organic milk & greens', dateStr: '2026-10-09' }
      ]
    };
  }
  return JSON.parse(raw);
}

function saveAppLocalData(data) {
  localStorage.setItem(APP_LOCAL_STORAGE_KEY, JSON.stringify(data));
}

// Check first time guide
function checkFirstTimeGuide() {
  const seen = localStorage.getItem(ONBOARDING_KEY);
  if (!seen) {
    setTimeout(() => {
      openModal('guide-modal');
    }, 400);
  }
}

// Calendar View Logic
const monthNames = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
];

function renderCalendar() {
  const monthYearEl = document.getElementById('calendar-month-year');
  monthYearEl.textContent = `${monthNames[currentDate.getMonth()]} ${currentDate.getFullYear()}`;

  const grid = document.getElementById('calendar-grid');
  grid.innerHTML = '';

  const year = currentDate.getFullYear();
  const month = currentDate.getMonth();

  const firstDayIndex = new Date(year, month, 1).getDay();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const prevMonthDays = new Date(year, month, 0).getDate();

  // Previous month trailing days
  for (let i = firstDayIndex; i > 0; i--) {
    const day = prevMonthDays - i + 1;
    const cell = document.createElement('div');
    cell.className = 'day-cell other-month';
    cell.textContent = day;
    grid.appendChild(cell);
  }

  const appData = getAppLocalData();

  // Current month days
  const today = new Date();
  for (let day = 1; day <= daysInMonth; day++) {
    const cell = document.createElement('div');
    cell.className = 'day-cell';
    cell.textContent = day;

    const thisDateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    const selectedDateStr = `${selectedDate.getFullYear()}-${String(selectedDate.getMonth() + 1).padStart(2, '0')}-${String(selectedDate.getDate()).padStart(2, '0')}`;

    if (day === today.getDate() && month === today.getMonth() && year === today.getFullYear()) {
      cell.classList.add('today');
    }

    if (thisDateStr === selectedDateStr) {
      cell.classList.add('selected');
    }

    // Has events dot
    const hasEvents = appData.events && appData.events.some(e => e.dateStr === thisDateStr);
    if (hasEvents) {
      const dot = document.createElement('span');
      dot.className = 'day-dot';
      cell.appendChild(dot);
    }

    // Date tap listener
    cell.addEventListener('click', () => handleDateClick(day, year, month));
    grid.appendChild(cell);
  }

  renderEvents();
}

// Secret Date Sequence Detection
function handleDateClick(day, year, month) {
  selectedDate = new Date(year, month, day);
  renderCalendar();

  // Append to sequence detector
  clearTimeout(tapBufferTimeout);
  currentTappedBuffer.push(day);

  const vaultData = getPersistentVaultData();
  const targetSeq = vaultData.sequence || secretSequence;

  if (currentTappedBuffer.length > targetSeq.length) {
    currentTappedBuffer.shift();
  }

  // Check if buffer matches
  if (currentTappedBuffer.length === targetSeq.length) {
    let matches = true;
    for (let i = 0; i < targetSeq.length; i++) {
      if (currentTappedBuffer[i] !== targetSeq[i]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      currentTappedBuffer = [];
      triggerSecretUnlock();
      return;
    }
  }

  // Reset buffer after 5 seconds of inactivity
  tapBufferTimeout = setTimeout(() => {
    currentTappedBuffer = [];
  }, 5000);
}

function triggerSecretUnlock() {
  document.getElementById('calendar-view').classList.remove('active');
  document.getElementById('vault-view').classList.add('active');
  renderVault();
}

function panicExit() {
  document.getElementById('vault-view').classList.remove('active');
  document.getElementById('calendar-view').classList.add('active');
  closeAllModals();
  currentTappedBuffer = [];
}

// Decoy Events Rendering
function renderEvents() {
  const label = document.getElementById('selected-date-label');
  label.textContent = `Events for ${monthNames[selectedDate.getMonth()].slice(0, 3)} ${selectedDate.getDate()}`;

  const list = document.getElementById('events-list');
  list.innerHTML = '';

  const selectedDateStr = `${selectedDate.getFullYear()}-${String(selectedDate.getMonth() + 1).padStart(2, '0')}-${String(selectedDate.getDate()).padStart(2, '0')}`;
  const appData = getAppLocalData();
  const dayEvents = (appData.events || []).filter(e => e.dateStr === selectedDateStr);

  if (dayEvents.length === 0) {
    list.innerHTML = `<div style="text-align: center; color: #94a3b8; font-size: 12px; padding: 20px 0;">No events planned for this day.</div>`;
    return;
  }

  dayEvents.forEach(ev => {
    const card = document.createElement('div');
    card.className = 'event-card';
    card.innerHTML = `
      <div>
        <h5>${escapeHtml(ev.title)}</h5>
        <p>${ev.time} • ${escapeHtml(ev.notes || '')}</p>
      </div>
      <button class="delete-event-btn" title="Delete event"><i class="fa-solid fa-trash"></i></button>
    `;
    card.querySelector('.delete-event-btn').addEventListener('click', () => {
      appData.events = appData.events.filter(e => e.id !== ev.id);
      saveAppLocalData(appData);
      renderCalendar();
    });
    list.appendChild(card);
  });
}

// Secret Vault Logic
function renderVault() {
  const vaultData = getPersistentVaultData();
  const items = vaultData.items || [];

  const photos = items.filter(x => x.type === 'photo');
  const videos = items.filter(x => x.type === 'video');
  const docs = items.filter(x => x.type === 'docs');
  const audio = items.filter(x => x.type === 'audio');
  const others = items.filter(x => x.type === 'others' || (x.type !== 'photo' && x.type !== 'video' && x.type !== 'docs' && x.type !== 'audio'));

  document.getElementById('count-all').textContent = items.length;
  document.getElementById('count-photos').textContent = photos.length;
  document.getElementById('count-videos').textContent = videos.length;
  document.getElementById('count-docs').textContent = docs.length;
  document.getElementById('count-audio').textContent = audio.length;
  document.getElementById('count-others').textContent = others.length;

  let filtered = items;
  if (currentTab === 'photos') filtered = photos;
  if (currentTab === 'videos') filtered = videos;
  if (currentTab === 'docs') filtered = docs;
  if (currentTab === 'audio') filtered = audio;
  if (currentTab === 'others') filtered = others;

  const grid = document.getElementById('media-grid');
  const emptyState = document.getElementById('vault-empty');
  grid.innerHTML = '';

  if (filtered.length === 0) {
    emptyState.classList.remove('hidden');
    return;
  } else {
    emptyState.classList.add('hidden');
  }

  filtered.forEach(item => {
    const card = document.createElement('div');
    card.className = 'media-card';

    let previewContent = '';
    if (item.type === 'photo') {
      previewContent = `<img src="${item.url || 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=300&q=80'}" alt="${escapeHtml(item.name)}" />`;
    } else if (item.type === 'video') {
      previewContent = `
        <div class="video-thumb">
          <i class="fa-solid fa-play play-icon"></i>
        </div>
      `;
    } else if (item.type === 'docs') {
      const isXlsx = (item.ext || '').includes('xls');
      const icon = isXlsx ? 'fa-file-excel' : 'fa-file-pdf';
      const col = isXlsx ? '#22c55e' : '#ef4444';
      previewContent = `
        <div class="file-thumb-icon">
          <i class="fa-solid ${icon}" style="font-size: 32px; color: ${col}; margin-bottom: 6px;"></i>
          <span style="font-size: 10px; color: ${col}; font-weight: bold; text-transform: uppercase;">${item.ext || 'doc'}</span>
        </div>
      `;
    } else if (item.type === 'audio') {
      previewContent = `
        <div class="file-thumb-icon">
          <i class="fa-solid fa-file-audio" style="font-size: 32px; color: #f97316; margin-bottom: 6px;"></i>
          <span style="font-size: 10px; color: #f97316; font-weight: bold; text-transform: uppercase;">AUDIO</span>
        </div>
      `;
    } else {
      previewContent = `
        <div class="file-thumb-icon">
          <i class="fa-solid fa-file-zipper" style="font-size: 32px; color: #64748b; margin-bottom: 6px;"></i>
          <span style="font-size: 10px; color: #94a3b8; font-weight: bold;">FILE</span>
        </div>
      `;
    }

    const downloadBadge = item.isDownloaded ? `<span style="position: absolute; top: 4px; left: 4px; background: rgba(56, 189, 248, 0.9); color: #000; font-size: 9px; font-weight: 800; padding: 2px 5px; border-radius: 4px;">PRIVATE</span>` : '';

    card.innerHTML = `
      ${previewContent}
      ${downloadBadge}
      <div class="media-info">
        <span class="media-title truncate">${escapeHtml(item.name)}</span>
        <span class="media-size">${formatBytes(item.size)}</span>
      </div>
    `;

    card.addEventListener('click', () => openViewer(item));
    grid.appendChild(card);
  });
}

// Simulate Private Browser Download directly into vault
function simulateBrowserDownload(fileName, category, sizeBytes) {
  const vaultData = getPersistentVaultData();
  let type = 'docs';
  let ext = fileName.split('.').pop() || 'dat';

  if (category === 'audio') type = 'audio';
  if (category === 'excel' || category === 'pdf') type = 'docs';

  const newItem = {
    id: 'dl-' + Date.now(),
    name: fileName,
    type: type,
    ext: ext,
    size: sizeBytes,
    isDownloaded: true,
    addedAt: new Date().toISOString()
  };

  vaultData.items.unshift(newItem);
  savePersistentVaultData(vaultData);

  document.getElementById('browser-download-status').textContent = 'Downloaded ' + fileName;
  alert(`🔒 Private Download Complete!\n"${fileName}" has been encrypted directly into HideX Vault.\nZero traces were left in phone's public Downloads folder!`);
  renderVault();
}

// Disguise Manager
const DISGUISES = [
  { id: 'CalendarAlias', name: 'Calendar Hidex', sub: 'Standard calendar & event planner', icon: 'fa-calendar-days', color: '#6366f1' },
  { id: 'CalculatorAlias', name: 'Calculator', sub: 'Standard scientific calculator', icon: 'fa-calculator', color: '#14b8a6' },
  { id: 'NotesAlias', name: 'Quick Notes', sub: 'Personal notebook & memos', icon: 'fa-note-sticky', color: '#f59e0b' },
  { id: 'ClockAlias', name: 'Clock & Timer', sub: 'Standard alarm & clock app', icon: 'fa-clock', color: '#3b82f6' },
  { id: 'WeatherAlias', name: 'Weather', sub: 'Local weather forecast', icon: 'fa-sun', color: '#f97316' },
];

function renderDisguises() {
  const list = document.getElementById('disguise-options-list');
  list.innerHTML = '';
  const current = localStorage.getItem(ACTIVE_DISGUISE_KEY) || 'CalendarAlias';

  DISGUISES.forEach(d => {
    const isActive = d.id === current;
    const item = document.createElement('div');
    item.className = 'disguise-item' + (isActive ? ' active' : '');
    item.innerHTML = `
      <div style="width: 36px; height: 36px; border-radius: 10px; background: ${d.color}; display: flex; align-items: center; justify-content: center; color: #fff;">
        <i class="fa-solid ${d.icon}"></i>
      </div>
      <div style="flex: 1;">
        <div style="font-weight: 700; font-size: 13px; color: #f8fafc;">${d.name}</div>
        <div style="font-size: 11px; color: #94a3b8;">${d.sub}</div>
      </div>
      ${isActive ? '<i class="fa-solid fa-circle-check" style="color: #818cf8; font-size: 18px;"></i>' : ''}
    `;

    item.addEventListener('click', () => {
      localStorage.setItem(ACTIVE_DISGUISE_KEY, d.id);
      renderDisguises();
      alert(`🎭 App Disguise Switched to: ${d.name}\nOn the phone home screen, the app will now appear with this icon and title!`);
    });

    list.appendChild(item);
  });
}

// Two-Step Password Change Inside Vault
let setupStep = 1; // 1: verify current, 2: set new, 3: confirm new
let verificationBuffer = [];
let newSeqBuffer = [];
let confirmSeqBuffer = [];

function openPasswordChangeModal() {
  setupStep = 1;
  verificationBuffer = [];
  newSeqBuffer = [];
  confirmSeqBuffer = [];
  updateSetupUI();
  openModal('setup-modal');
}

function updateSetupUI() {
  const titleEl = document.getElementById('setup-step-title');
  const hintEl = document.getElementById('setup-step-hint');
  const actionBtn = document.getElementById('setup-action-btn');
  const errorEl = document.getElementById('setup-error-msg');
  errorEl.textContent = '';

  let activeBuffer = [];
  if (setupStep === 1) {
    titleEl.textContent = 'Step 1 of 2: Verify Current Password';
    hintEl.textContent = 'To change your hidden vault password, first tap your CURRENT 4 dates to verify your identity.';
    actionBtn.textContent = 'Verify Current';
    activeBuffer = verificationBuffer;
    actionBtn.disabled = activeBuffer.length !== 4;
  } else if (setupStep === 2) {
    titleEl.textContent = 'Step 2 of 2: Set New Combination';
    hintEl.textContent = 'Identity verified! Now tap your NEW 4 dates on the grid in order.';
    actionBtn.textContent = 'Next: Confirm';
    activeBuffer = newSeqBuffer;
    actionBtn.disabled = activeBuffer.length !== 4;
  } else if (setupStep === 3) {
    titleEl.textContent = 'Confirm New Combination';
    hintEl.textContent = 'Please re-tap your NEW 4 dates to confirm.';
    actionBtn.textContent = 'Save New Password';
    activeBuffer = confirmSeqBuffer;
    actionBtn.disabled = activeBuffer.length !== 4;
  }

  for (let i = 0; i < 4; i++) {
    const slot = document.getElementById(`slot-${i}`);
    slot.textContent = i < activeBuffer.length ? activeBuffer[i] : '?';
    if (i < activeBuffer.length) {
      slot.classList.add('filled');
    } else {
      slot.classList.remove('filled');
    }
  }
}

function handleSetupDateTap(day) {
  if (setupStep === 1) {
    if (verificationBuffer.length < 4) verificationBuffer.push(day);
  } else if (setupStep === 2) {
    if (newSeqBuffer.length < 4) newSeqBuffer.push(day);
  } else if (setupStep === 3) {
    if (confirmSeqBuffer.length < 4) confirmSeqBuffer.push(day);
  }
  updateSetupUI();
}

function handleSetupAction() {
  const vaultData = getPersistentVaultData();
  const currentSeq = vaultData.sequence || secretSequence;

  if (setupStep === 1) {
    // Verify current
    let matches = verificationBuffer.length === currentSeq.length;
    for (let i = 0; i < currentSeq.length; i++) {
      if (verificationBuffer[i] !== currentSeq[i]) matches = false;
    }

    if (matches) {
      setupStep = 2;
      updateSetupUI();
    } else {
      document.getElementById('setup-error-msg').textContent = 'Incorrect current password! Please try again.';
      verificationBuffer = [];
      updateSetupUI();
    }
  } else if (setupStep === 2) {
    if (newSeqBuffer.length === 4) {
      setupStep = 3;
      confirmSeqBuffer = [];
      updateSetupUI();
    }
  } else if (setupStep === 3) {
    let matches = true;
    for (let i = 0; i < 4; i++) {
      if (newSeqBuffer[i] !== confirmSeqBuffer[i]) matches = false;
    }

    if (!matches) {
      document.getElementById('setup-error-msg').textContent = 'Confirmation does not match! Re-enter confirmation.';
      confirmSeqBuffer = [];
      updateSetupUI();
      return;
    }

    // Successfully saved!
    vaultData.sequence = [...newSeqBuffer];
    savePersistentVaultData(vaultData);
    closeModal('setup-modal');
    alert(`✅ Secret vault combination updated successfully to: ${newSeqBuffer.join(' - ')}!`);
  }
}

// Media Viewer Logic
function openViewer(item) {
  activeViewerItem = item;
  const modal = document.getElementById('viewer-modal');
  const title = document.getElementById('modal-title');
  const body = document.getElementById('modal-body');

  title.textContent = item.name;
  body.innerHTML = '';

  if (item.type === 'photo') {
    body.innerHTML = `<img src="${item.url || 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=600&q=80'}" alt="${escapeHtml(item.name)}" />`;
  } else if (item.type === 'video') {
    body.innerHTML = `
      <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: #fff;">
        <i class="fa-solid fa-circle-play" style="font-size: 64px; color: #38bdf8; margin-bottom: 14px;"></i>
        <p>Encrypted Video Playback</p>
        <span style="font-size: 11px; color: #94a3b8; margin-top: 4px;">Decrypted on-the-fly directly in temporary memory</span>
      </div>
    `;
  } else {
    body.innerHTML = `
      <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: #fff;">
        <i class="fa-solid fa-file-shield" style="font-size: 64px; color: #22c55e; margin-bottom: 14px;"></i>
        <h4 style="margin-bottom: 6px;">${escapeHtml(item.name)}</h4>
        <p style="font-size: 13px; color: #94a3b8;">Encrypted Document (${(item.ext || 'doc').toUpperCase()})</p>
        <button onclick="alert('File decrypted in temporary memory and opened!')" class="btn primary" style="margin-top: 16px;">
          <i class="fa-solid fa-arrow-up-right-from-square"></i> Open Securely
        </button>
      </div>
    `;
  }

  openModal('viewer-modal');
}

// Helper Utilities
function formatBytes(bytes) {
  if (!bytes) return '0 B';
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

function openModal(id) {
  const modal = document.getElementById(id);
  if (modal) modal.classList.remove('hidden');
}

function closeModal(id) {
  const modal = document.getElementById(id);
  if (modal) modal.classList.add('hidden');
}

function closeAllModals() {
  document.querySelectorAll('.modal').forEach(m => m.classList.add('hidden'));
}

// Initialize Everything
document.addEventListener('DOMContentLoaded', () => {
  renderCalendar();
  checkFirstTimeGuide();

  // Navigation
  document.getElementById('prev-month-btn').addEventListener('click', () => {
    currentDate = new Date(currentDate.getFullYear(), currentDate.getMonth() - 1, 1);
    renderCalendar();
  });

  document.getElementById('next-month-btn').addEventListener('click', () => {
    currentDate = new Date(currentDate.getFullYear(), currentDate.getMonth() + 1, 1);
    renderCalendar();
  });

  document.getElementById('today-btn').addEventListener('click', () => {
    currentDate = new Date();
    selectedDate = new Date();
    renderCalendar();
  });

  // Theme toggle
  document.getElementById('theme-toggle-btn').addEventListener('click', () => {
    const screen = document.querySelector('.screen');
    const isDark = screen.classList.toggle('dark-theme');
    const icon = document.querySelector('#theme-toggle-btn i');
    icon.className = isDark ? 'fa-solid fa-sun' : 'fa-solid fa-moon';
  });

  // Guide
  document.getElementById('guide-info-btn').addEventListener('click', () => openModal('guide-modal'));
  document.getElementById('guide-close-btn').addEventListener('click', () => closeModal('guide-modal'));
  document.getElementById('guide-gotit-btn').addEventListener('click', () => {
    localStorage.setItem(ONBOARDING_KEY, 'true');
    closeModal('guide-modal');
  });

  // Creator Info
  document.getElementById('creator-info-btn').addEventListener('click', () => openModal('creator-modal'));
  document.getElementById('creator-close-btn').addEventListener('click', () => closeModal('creator-modal'));

  // Vault Buttons
  document.getElementById('panic-exit-btn').addEventListener('click', panicExit);
  document.getElementById('vault-info-btn').addEventListener('click', () => {
    alert("🔒 HideX Persistent Protection:\nAll files are encrypted with AES-256 and stored in phone storage (/storage/emulated/0/Documents/.calendar_vault).\nEven if the app is uninstalled, your files stay safe and will be restored when reinstalled!");
  });

  // Browser modal
  document.getElementById('browser-open-btn').addEventListener('click', () => openModal('browser-modal'));
  document.getElementById('browser-close-btn').addEventListener('click', () => closeModal('browser-modal'));
  document.getElementById('browser-go-btn').addEventListener('click', () => {
    const url = document.getElementById('browser-url-input').value;
    alert(`Navigating securely to: ${url}\nZero trace saved on phone!`);
  });
  document.getElementById('browser-download-sample-btn').addEventListener('click', () => {
    simulateBrowserDownload('Downloaded_Doc_' + Date.now().toString().slice(-4) + '.pdf', 'pdf', 1200000);
  });

  // Disguise modal
  document.getElementById('disguise-open-btn').addEventListener('click', () => {
    renderDisguises();
    openModal('disguise-modal');
  });
  document.getElementById('disguise-close-btn').addEventListener('click', () => closeModal('disguise-modal'));

  // Password Setup modal
  document.getElementById('change-seq-btn').addEventListener('click', openPasswordChangeModal);
  document.getElementById('setup-close-btn').addEventListener('click', () => closeModal('setup-modal'));
  document.getElementById('setup-clear-btn').addEventListener('click', () => {
    if (setupStep === 1) verificationBuffer = [];
    if (setupStep === 2) newSeqBuffer = [];
    if (setupStep === 3) confirmSeqBuffer = [];
    updateSetupUI();
  });
  document.getElementById('setup-action-btn').addEventListener('click', handleSetupAction);

  // Setup grid numbers (1 to 31)
  const setupGrid = document.getElementById('setup-grid');
  for (let i = 1; i <= 31; i++) {
    const btn = document.createElement('button');
    btn.className = 'grid-day-btn';
    btn.textContent = i;
    btn.addEventListener('click', () => handleSetupDateTap(i));
    setupGrid.appendChild(btn);
  }

  // Vault Tabs (6 tabs)
  document.querySelectorAll('.vault-tabs .tab-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      document.querySelectorAll('.vault-tabs .tab-btn').forEach(b => b.classList.remove('active'));
      e.target.classList.add('active');
      currentTab = e.target.dataset.tab;
      renderVault();
    });
  });

  // Add Event Modal
  document.getElementById('add-event-btn').addEventListener('click', () => openModal('event-modal'));
  document.getElementById('event-close-btn').addEventListener('click', () => closeModal('event-modal'));
  document.getElementById('save-event-btn').addEventListener('click', () => {
    const title = document.getElementById('event-title-input').value.trim();
    const time = document.getElementById('event-time-input').value;
    const notes = document.getElementById('event-notes-input').value.trim();

    if (!title) {
      alert('Please enter an event title');
      return;
    }

    const appData = getAppLocalData();
    const selectedDateStr = `${selectedDate.getFullYear()}-${String(selectedDate.getMonth() + 1).padStart(2, '0')}-${String(selectedDate.getDate()).padStart(2, '0')}`;

    appData.events.push({
      id: 'ev-' + Date.now(),
      title: title,
      time: time,
      notes: notes,
      dateStr: selectedDateStr
    });

    saveAppLocalData(appData);
    closeModal('event-modal');
    document.getElementById('event-title-input').value = '';
    document.getElementById('event-notes-input').value = '';
    renderCalendar();
  });

  // Import FAB
  const fileInput = document.getElementById('media-file-input');
  document.getElementById('import-fab').addEventListener('click', () => fileInput.click());

  fileInput.addEventListener('change', (e) => {
    const files = Array.from(e.target.files);
    if (!files.length) return;

    const vaultData = getPersistentVaultData();

    files.forEach(file => {
      let type = 'others';
      const name = file.name.toLowerCase();
      const ext = name.split('.').pop() || '';

      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].includes(ext)) type = 'photo';
      else if (['mp4', 'mov', 'avi', 'mkv'].includes(ext)) type = 'video';
      else if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'].includes(ext)) type = 'docs';
      else if (['mp3', 'wav', 'm4a', 'aac'].includes(ext)) type = 'audio';

      vaultData.items.unshift({
        id: 'user-' + Date.now() + Math.random().toString(36).substr(2, 4),
        name: file.name,
        type: type,
        ext: ext,
        size: file.size,
        url: type === 'photo' ? URL.createObjectURL(file) : null,
        addedAt: new Date().toISOString()
      });
    });

    savePersistentVaultData(vaultData);
    renderVault();
    alert(`🔒 Successfully encrypted and saved ${files.length} file(s) into HideX Vault!`);
  });

  // Media Viewer modal actions
  document.getElementById('modal-close-btn').addEventListener('click', () => closeModal('viewer-modal'));
  document.getElementById('modal-export-btn').addEventListener('click', () => {
    if (activeViewerItem) {
      alert(`Exported "${activeViewerItem.name}" to phone's public storage!`);
      closeModal('viewer-modal');
    }
  });
  document.getElementById('modal-delete-btn').addEventListener('click', () => {
    if (activeViewerItem && confirm(`Permanently delete "${activeViewerItem.name}" from HideX Vault?`)) {
      const vaultData = getPersistentVaultData();
      vaultData.items = vaultData.items.filter(x => x.id !== activeViewerItem.id);
      savePersistentVaultData(vaultData);
      closeModal('viewer-modal');
      renderVault();
    }
  });

  // Simulator Sidebar Uninstall & Reinstall buttons
  const uninstallBtn = document.getElementById('simulate-uninstall-btn');
  const reinstallBtn = document.getElementById('simulate-reinstall-btn');
  const uninstallStatus = document.getElementById('uninstall-status');

  uninstallBtn.addEventListener('click', () => {
    localStorage.removeItem(APP_LOCAL_STORAGE_KEY);
    localStorage.removeItem(ONBOARDING_KEY);
    localStorage.removeItem(ACTIVE_DISGUISE_KEY);

    uninstallBtn.style.display = 'none';
    reinstallBtn.style.display = 'block';
    uninstallStatus.innerHTML = '<span style="color: #ef4444; font-weight: bold;">App has been UNINSTALLED.</span> Local decoy data was wiped, but persistent external vault files remain intact in simulated <code>Documents/.calendar_vault/</code>.';

    panicExit();
    renderCalendar();
  });

  reinstallBtn.addEventListener('click', () => {
    reinstallBtn.style.display = 'none';
    uninstallBtn.style.display = 'block';
    uninstallStatus.innerHTML = '<span style="color: #22c55e; font-weight: bold;">App REINSTALLED!</span> Secret vault files survived! Tap <strong>7 ➔ 14 ➔ 21 ➔ 28</strong> to access all your preserved files.';

    checkFirstTimeGuide();
    renderCalendar();
  });
});
