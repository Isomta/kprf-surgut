// Глобальные переменные
let currentDeputat = null;
let lastAddress = null;
let map = null;

// Скрыть внешнюю карту при выборе депутата
function hideExternalMap() {
    const container = document.getElementById('externalMapContainer');
    if (container) {
        container.style.display = 'none';
    }
}

// Загрузка списка улиц для datalist
async function loadStreets() {
    const streetList = document.getElementById('streetList');
    const modalStreetList = document.getElementById('modalStreetList');
    
    if (!streetList && !modalStreetList) return;
    
    const response = await fetch('/api/streets');
    const streets = await response.json();
    
    if (streetList) {
        streetList.innerHTML = '';
        streets.forEach(s => {
            const option = document.createElement('option');
            option.value = s;
            streetList.appendChild(option);
        });
    }
    
    if (modalStreetList) {
        modalStreetList.innerHTML = '';
        streets.forEach(s => {
            const option = document.createElement('option');
            option.value = s;
            modalStreetList.appendChild(option);
        });
    }
}

// Загрузка домов для выбранной улицы
async function loadHouses(street, targetListId) {
    const list = document.getElementById(targetListId);
    if (!list) return;
    
    if (!street) {
        list.innerHTML = '';
        return;
    }
    const response = await fetch(`/api/houses/${encodeURIComponent(street)}`);
    const houses = await response.json();
    list.innerHTML = '';
    houses.forEach(h => {
        const option = document.createElement('option');
        option.value = h;
        list.appendChild(option);
    });
}

// Инициализация карты
function initMap(address) {
    const mapContainer = document.getElementById('map');
    if (!mapContainer) {
        console.log('Контейнер карты не найден');
        return;
    }
    
    console.log('Инициализация карты для адреса:', address);
    mapContainer.style.display = 'block';
    
    if (map) {
        map.remove();
    }
    
    let searchQuery = address;
    searchQuery = searchQuery
        .replace(/г\./g, '')
        .replace(/ул\./g, '')
        .replace(/д\./g, '')
        .replace(/кв\.\s*\d+/g, '')
        .replace(/[.,]/g, '')
        .replace(/\s+/g, ' ')
        .trim();
    
    console.log('Поиск по запросу:', searchQuery);
    
    fetch(`https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(searchQuery)}&limit=1`)
        .then(response => response.json())
        .then(data => {
            console.log('Результат геокодирования:', data);
            if (data && data.length > 0) {
                const lat = data[0].lat;
                const lon = data[0].lon;
                
                map = L.map('map').setView([lat, lon], 15);
                L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                }).addTo(map);
                
                L.marker([lat, lon]).addTo(map)
                    .bindPopup(`<b>Приемная депутата</b><br>${address}`)
                    .openPopup();
                
                setTimeout(() => {
                    map.invalidateSize();
                }, 100);
            } else {
                mapContainer.style.display = 'none';
                console.log('Адрес не найден на карте');
            }
        })
        .catch(error => {
            console.error('Ошибка геокодирования:', error);
            mapContainer.style.display = 'none';
        });
}

// Поиск депутата
async function searchDeputat() {
    const street = document.getElementById('street').value.trim();
    const house = document.getElementById('house').value.trim();
    const errorDiv = document.getElementById('searchError');
    if (!street || !house) {
        errorDiv.innerText = 'Введите улицу и номер дома';
        return;
    }
    try {
        const response = await fetch('/api/deputat_by_address', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({street, house})
        });
        if (!response.ok) {
            const error = await response.json();
            errorDiv.innerText = error.error;
            document.getElementById('deputatInfo').style.display = 'none';
            return;
        }
        const data = await response.json();
        currentDeputat = data.deputat;
        document.getElementById('deputatName').innerText = data.deputat.fio;
        document.getElementById('uchastok').innerText = data.deputat.uchastok;
        document.getElementById('birthDate').innerText = data.deputat.birth_date;
        document.getElementById('education').innerText = data.deputat.education;
        document.getElementById('experience').innerText = data.deputat.experience;
        document.getElementById('address').innerText = data.deputat.reception_address;
        document.getElementById('phone').innerText = data.deputat.phone;
        document.getElementById('email').innerText = data.deputat.email;
        document.getElementById('deputatPhotoImg').src = data.deputat.photo || '/static/photos/default.png';

        if (data.deputat.reception_address) {
            initMap(data.deputat.reception_address);
        }
        
        document.getElementById('totalAppeals').innerText = data.stats.total;
        document.getElementById('newAppeals').innerText = data.stats.new;
        document.getElementById('inWorkAppeals').innerText = data.stats.in_work;
        document.getElementById('completedAppeals').innerText = data.stats.completed;
        document.getElementById('rejectedAppeals').innerText = data.stats.rejected;
        const topicsDiv = document.getElementById('topicsStats');
        topicsDiv.innerHTML = '';
        for (const [topic, count] of Object.entries(data.topics_stats)) {
            topicsDiv.innerHTML += `<div class="topic-tag">${topic}: ${count}</div>`;
        }
        document.getElementById('deputatInfo').style.display = 'block';
        errorDiv.innerText = '';
        lastAddress = {street, house};
        
        // === СКРЫВАЕМ ВНЕШНЮЮ КАРТУ ПРИ УСПЕШНОМ ПОИСКЕ ===
        hideExternalMap();
        
    } catch (error) {
        errorDiv.innerText = 'Ошибка при загрузке данных';
    }
}

// Загрузка тем для выпадающего списка
async function loadTopics() {
    const select = document.getElementById('topic');
    if (!select) return;
    
    const response = await fetch('/api/topics');
    const topics = await response.json();
    select.innerHTML = '<option value="">Выберите тему</option>';
    topics.forEach(topic => {
        select.innerHTML += `<option value="${topic}">${topic}</option>`;
    });
}

// Открыть модальное окно обращения
function openAppealForm() {
    if (!currentDeputat) {
        alert('Сначала найдите депутата по вашему адресу');
        return;
    }
    document.getElementById('appealModal').style.display = 'flex';
    if (lastAddress) {
        document.getElementById('modalStreet').value = lastAddress.street;
        document.getElementById('modalHouse').value = lastAddress.house;
        loadHouses(lastAddress.street, 'modalHouseList');
    }
}

function closeModal() {
    document.getElementById('appealModal').style.display = 'none';
    document.getElementById('appealForm').reset();
}

// Отправка обращения
const appealForm = document.getElementById('appealForm');
if (appealForm) {
    appealForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const street = document.getElementById('modalStreet').value.trim();
        const house = document.getElementById('modalHouse').value.trim();
        const topic = document.getElementById('topic').value;
        const text = document.getElementById('text').value.trim();
        const fio = document.getElementById('fio').value.trim();
        const phone = document.getElementById('phoneInput').value.trim();
        const email = document.getElementById('emailInput').value.trim();
        const needVisit = document.getElementById('needVisit').checked;
        const consent = document.getElementById('consent').checked;
        if (!consent) {
            alert('Необходимо согласие на обработку персональных данных');
            return;
        }
        if (!street || !house || !topic || !text) {
            alert('Заполните обязательные поля: адрес, тему и текст обращения');
            return;
        }
        try {
            const response = await fetch('/api/create_appeal', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({street, house, topic, text, fio, phone, email, need_visit: needVisit})
            });
            if (response.ok) {
                alert('Обращение успешно отправлено!');
                closeModal();
                if (street === lastAddress?.street && house === lastAddress?.house) {
                    searchDeputat();
                }
            } else {
                const error = await response.json();
                alert('Ошибка: ' + error.error);
            }
        } catch (error) {
            alert('Ошибка при отправке обращения');
        }
    });
}

// Установка текущего года
document.addEventListener('DOMContentLoaded', () => {
    const yearSpan = document.getElementById('currentYear');
    if (yearSpan) {
        yearSpan.textContent = new Date().getFullYear();
    }
});

// Инициализация после загрузки DOM
document.addEventListener('DOMContentLoaded', () => {
    if (document.getElementById('streetList')) {
        loadStreets();
    }
    if (document.getElementById('topic')) {
        loadTopics();
    }
    
    const streetInput = document.getElementById('street');
    const modalStreetInput = document.getElementById('modalStreet');
    
    if (streetInput) {
        streetInput.addEventListener('input', (e) => {
            loadHouses(e.target.value, 'houseList');
        });
    }
    
    if (modalStreetInput) {
        modalStreetInput.addEventListener('input', (e) => {
            loadHouses(e.target.value, 'modalHouseList');
        });
    }
});

// Автопоказ депутата при переходе по ?deputat_id=X
document.addEventListener('DOMContentLoaded', async () => {
    const urlParams = new URLSearchParams(window.location.search);
    const deputatId = urlParams.get('deputat_id');
    
    if (deputatId && document.getElementById('deputatInfo')) {
        try {
            const response = await fetch(`/api/deputat/${deputatId}`);
            
            if (!response.ok) {
                const err = await response.json();
                document.getElementById('searchError').innerText = err.error || 'Депутат не найден';
                return;
            }
            
            const data = await response.json();
            const deputat = data.deputat;
            
            currentDeputat = deputat;
            document.getElementById('deputatName').innerText = deputat.fio;
            document.getElementById('uchastok').innerText = deputat.uchastok;
            document.getElementById('birthDate').innerText = deputat.birth_date || '—';
            document.getElementById('education').innerText = deputat.education || '—';
            document.getElementById('experience').innerText = deputat.experience || '—';
            document.getElementById('address').innerText = deputat.reception_address || '—';
            document.getElementById('phone').innerHTML = deputat.phone 
                ? `<a href="tel:${deputat.phone}" style="color:#3498db;text-decoration:none">${deputat.phone}</a>` 
                : '—';
            document.getElementById('email').innerHTML = deputat.email 
                ? `<a href="mailto:${deputat.email}" style="color:#3498db;text-decoration:none">${deputat.email}</a>` 
                : '—';
            document.getElementById('deputatPhotoImg').src = deputat.photo || '/static/photos/default.png';
            
            if (deputat.reception_address) {
                initMap(deputat.reception_address);
            }
            
            if (data.stats) {
                document.getElementById('totalAppeals').innerText = data.stats.total;
                document.getElementById('newAppeals').innerText = data.stats.new;
                document.getElementById('inWorkAppeals').innerText = data.stats.in_work;
                document.getElementById('completedAppeals').innerText = data.stats.completed;
                document.getElementById('rejectedAppeals').innerText = data.stats.rejected;
            }
            
            const topicsDiv = document.getElementById('topicsStats');
            topicsDiv.innerHTML = '';
            if (data.topics_stats && Object.keys(data.topics_stats).length > 0) {
                for (const [topic, count] of Object.entries(data.topics_stats)) {
                    topicsDiv.innerHTML += `<div class="topic-tag">${topic}: ${count}</div>`;
                }
            } else {
                topicsDiv.innerHTML = '<em>Нет обращений</em>';
            }
            
            document.getElementById('deputatInfo').style.display = 'block';
            document.getElementById('searchError').innerText = '';
            document.getElementById('deputatInfo').scrollIntoView({ behavior: 'smooth' });
            
            // === СКРЫВАЕМ ВНЕШНЮЮ КАРТУ ПРИ АВТОЗАГРУЗКЕ ===
            hideExternalMap();
            
        } catch (e) {
            console.error('Ошибка автозагрузки депутата:', e);
            document.getElementById('searchError').innerText = 'Ошибка при загрузке данных';
        }
    }
});