/**
 * index.js - Логика главной страницы
 * Управление: поиск депутата, карточка, карта, модальные окна, обращения, голосования
 */

let currentUchastok = null; // Участок текущего выбранного депутата
let leafletMap = null;      // Экземпляр карты Leaflet

document.addEventListener('DOMContentLoaded', () => {
    loadStreets();
    loadTopics();
    autoLoadDeputatFromUrl();
    setupModalClickOutside();
    setupAppealForm();
});

// ==========================================
// ЗАГРУЗКА СПРАВОЧНИКОВ
// ==========================================
async function loadStreets() {
    try {
        const res = await fetch('/api/streets');
        const streets = await res.json();
        const list = document.getElementById('streetList');
        if (list) list.innerHTML = streets.map(s => `<option value="${s}">`).join('');
    } catch (e) { console.error('Ошибка загрузки улиц:', e); }
}

async function loadHouses(street, targetId, uchastok = null) {
    if (!street) return;
    try {
        let url = `/api/houses/${encodeURIComponent(street)}`;
        if (uchastok) url += `?uchastok=${uchastok}`;
        
        const res = await fetch(url);
        const houses = await res.json();
        const el = document.getElementById(targetId);
        if (el) el.innerHTML = houses.map(h => `<option value="${h}">`).join('');
    } catch (e) { console.error('Ошибка загрузки домов:', e); }
}

async function loadTopics() {
    try {
        const res = await fetch('/api/topics');
        const topics = await res.json();
        const select = document.getElementById('topic');
        if (select) select.innerHTML = topics.map(t => `<option value="${t}">${t}</option>`).join('');
    } catch (e) { console.error('Ошибка загрузки тем:', e); }
}

// ==========================================
// ОБРАБОТЧИКИ ИЗМЕНЕНИЯ ПОЛЕЙ
// ==========================================
document.addEventListener('change', (e) => {
    // Главная форма поиска (без фильтра по участку)
    if (e.target.id === 'street') {
        document.getElementById('houseList').innerHTML = '';
        document.getElementById('house').value = '';
        loadHouses(e.target.value, 'houseList');
    }
    // Форма обращения (с фильтром по участку)
    if (e.target.id === 'modalStreet') {
        document.getElementById('modalHouseList').innerHTML = '';
        document.getElementById('modalHouse').value = '';
        loadHouses(e.target.value, 'modalHouseList', currentUchastok);
    }
});

// ==========================================
// ПОИСК И ОТРИСОВКА ДЕПУТАТА
// ==========================================
window.searchDeputat = async () => {
    const street = document.getElementById('street').value.trim();
    const house = document.getElementById('house').value.trim();
    const errEl = document.getElementById('searchError');
    const infoEl = document.getElementById('deputatInfo');
    
    errEl.textContent = '';
    infoEl.style.display = 'none';
    
    if (!street || !house) { errEl.textContent = 'Заполните улицу и дом'; return; }
    
    errEl.textContent = 'Ищем...';
    try {
        const res = await fetch('/api/deputat_by_address', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ street, house })
        });
        const data = await res.json();
        
        if (!res.ok) { errEl.textContent = data.error || 'Адрес не найден в границах участков'; return; }
        
        renderDeputatCard(data.deputat, data.stats, data.topics_stats);
        errEl.textContent = '';
    } catch (e) { errEl.textContent = 'Ошибка соединения'; console.error(e); }
};

async function autoLoadDeputatFromUrl() {
    const params = new URLSearchParams(window.location.search);
    const deputatId = params.get('deputat_id');
    if (deputatId) {
        try {
            const res = await fetch(`/api/deputat/${deputatId}`);
            if (res.ok) {
                const data = await res.json();
                renderDeputatCard(data.deputat, data.stats, data.topics_stats);
                document.getElementById('deputatInfo').scrollIntoView({ behavior: 'smooth' });
            }
        } catch (e) { console.error(e); }
    }
}

function renderDeputatCard(deputat, stats, topics) {
    document.getElementById('deputatName').textContent = deputat.fio;
    document.getElementById('uchastok').textContent = deputat.uchastok;
    document.getElementById('birthDate').textContent = deputat.birth_date || '—';
    document.getElementById('education').textContent = deputat.education || '—';
    document.getElementById('experience').textContent = deputat.experience || '—';
    document.getElementById('address').textContent = deputat.reception_address || '—';
    document.getElementById('phone').textContent = deputat.phone || '—';
    document.getElementById('email').textContent = deputat.email || '—';
    document.getElementById('deputatPhotoImg').src = deputat.photo || '/static/photos/default.png';
    
    document.getElementById('totalAppeals').textContent = stats.total;
    document.getElementById('newAppeals').textContent = stats.new;
    document.getElementById('inWorkAppeals').textContent = stats.in_work;
    document.getElementById('completedAppeals').textContent = stats.completed;
    document.getElementById('rejectedAppeals').textContent = stats.rejected;
    
    const topicsContainer = document.getElementById('topicsStats');
    topicsContainer.innerHTML = Object.entries(topics)
        .sort((a, b) => b[1] - a[1])
        .map(([topic, count]) => `<span class="topic-tag">${topic} (${count})</span>`)
        .join('');
        
    document.getElementById('deputatInfo').style.display = 'block';
    currentUchastok = deputat.uchastok; // Сохраняем участок для фильтрации адресов
    
    // Инициализация карты с задержкой (контейнер должен стать видимым)
    document.getElementById('map').style.display = 'block';
    setTimeout(initMap, 150);
}

// ==========================================
// КАРТА (LEAFLET)
// ==========================================
function initMap() {
    const mapContainer = document.getElementById('map');
    if (!mapContainer || mapContainer.style.display === 'none') return;

    if (leafletMap) {
        leafletMap.invalidateSize();
        return;
    }

    // Центр Сургута (можно заменить на координаты из БД, если добавите поля lat/lon)
    leafletMap = L.map('map').setView([61.2500, 73.3833], 13);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap contributors'
    }).addTo(leafletMap);

    L.marker([61.2500, 73.3833]).addTo(leafletMap)
        .bindPopup('Приёмная кандидата')
        .openPopup();
}

// ==========================================
// МОДАЛЬНЫЕ ОКНА
// ==========================================
window.openDeputatDetails = async () => {
    const deputatId = document.getElementById('uchastok')?.textContent;
    if (!deputatId) return;
    
    try {
        const res = await fetch(`/api/deputat/${deputatId}/details`);
        const data = await res.json();
        
        document.getElementById('modalBiography').textContent = data.biography;
        const pointsList = document.getElementById('campaignPointsList');
        pointsList.innerHTML = data.points.map(p => {
            const voted = localStorage.getItem(`vote_${p.id}`);
            const disabled = voted ? 'disabled' : '';
            return `
                <div style="padding: 12px; background: #f8f9fa; border-radius: 8px; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px;">
                    <span style="flex: 1;">${p.text}</span>
                    <div style="display: flex; gap: 8px;">
                        <button class="btn-small" onclick="voteCampaign(${p.id}, 'for')" ${disabled}>👍 ${p.for}</button>
                        <button class="btn-small" onclick="voteCampaign(${p.id}, 'against')" ${disabled}>👎 ${p.against}</button>
                    </div>
                </div>
            `;
        }).join('');
        
        document.getElementById('detailsModal').style.display = 'flex';
    } catch (e) { console.error('Ошибка загрузки биографии:', e); }
};

window.closeDeputatDetails = () => document.getElementById('detailsModal').style.display = 'none';
window.closeModal = () => {
    document.getElementById('appealModal').style.display = 'none';
    const form = document.getElementById('appealForm');
    if (form) form.dataset.submitting = 'false';
};

function setupModalClickOutside() {
    document.querySelectorAll('.modal-overlay').forEach(modal => {
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                modal.style.display = 'none';
                const form = modal.querySelector('#appealForm');
                if (form) form.dataset.submitting = 'false';
            }
        });
    });
}

// ==========================================
// ГОЛОСОВАНИЕ
// ==========================================
window.voteCampaign = async (pointId, type) => {
    try {
        const res = await fetch('/api/campaign/vote', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ point_id: pointId, type })
        });
        const data = await res.json();
        if (res.ok) {
            localStorage.setItem(`vote_${pointId}`, '1');
            window.openDeputatDetails(); // Обновляем кнопки
        } else {
            alert(data.error || 'Ошибка голосования');
        }
    } catch (e) { alert('Ошибка соединения'); }
};

// ==========================================
// ФОРМА ОБРАЩЕНИЯ
// ==========================================
window.openAppealForm = async () => {
    if (!currentUchastok) {
        alert('⚠️ Сначала найдите депутата, чтобы написать обращение.');
        return;
    }
    
    // Очищаем поля и списки
    document.getElementById('modalStreetList').innerHTML = '';
    document.getElementById('modalHouseList').innerHTML = '';
    document.getElementById('modalStreet').value = '';
    document.getElementById('modalHouse').value = '';
    
    // Загружаем ТОЛЬКО улицы текущего участка
    try {
        const res = await fetch(`/api/streets?uchastok=${currentUchastok}`);
        const streets = await res.json();
        document.getElementById('modalStreetList').innerHTML = streets.map(s => `<option value="${s}">`).join('');
    } catch (e) { console.error('Ошибка загрузки улиц:', e); }
    
    document.getElementById('appealModal').style.display = 'flex';
};

function setupAppealForm() {
    const form = document.getElementById('appealForm');
    if (!form) return;
    
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (form.dataset.submitting === 'true') return; // Защита от дубля
        form.dataset.submitting = 'true';
        
        if (!document.getElementById('consent').checked) {
            alert('Необходимо согласие на обработку персональных данных');
            form.dataset.submitting = 'false';
            return;
        }
        
        const data = {
            street: document.getElementById('modalStreet').value.trim(),
            house: document.getElementById('modalHouse').value.trim(),
            topic: document.getElementById('topic').value,
            text: document.getElementById('text').value.trim(),
            fio: document.getElementById('fio').value.trim(),
            phone: document.getElementById('phoneInput').value.trim(),
            email: document.getElementById('emailInput').value.trim(),
            need_visit: document.getElementById('needVisit').checked
        };
        
        try {
            const res = await fetch('/api/create_appeal', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data)
            });
            const result = await res.json();
            
            if (res.ok) {
                alert('✅ Обращение успешно отправлено!');
                window.closeModal();
                form.reset();
            } else {
                alert('❌ ' + (result.error || 'Ошибка отправки'));
            }
        } catch (e) {
            alert('❌ Ошибка соединения');
        } finally {
            form.dataset.submitting = 'false';
        }
    });
}