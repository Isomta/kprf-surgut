// admin.js
function applyFilters() {
    const searchText = document.getElementById('searchInput')?.value.toLowerCase() || '';
    const statusFilter = document.getElementById('statusFilter')?.value || '';
    const topicFilter = document.getElementById('topicFilter')?.value || '';
    const visitFilter = document.getElementById('needVisitFilter')?.value || '';
    const dateFilter = document.getElementById('dateFilter')?.value || '';
    
    const today = new Date().toISOString().split('T')[0];
    const weekAgo = new Date(Date.now() - 7*24*60*60*1000).toISOString().split('T')[0];
    const monthAgo = new Date(Date.now() - 30*24*60*60*1000).toISOString().split('T')[0];
    
    const rows = document.querySelectorAll('#appealsTable tbody tr');
    let visibleCount = 0;
    
    rows.forEach(row => {
        let show = true;
        const rowDate = row.dataset.date;
        
        if (statusFilter && row.dataset.status !== statusFilter) show = false;
        if (topicFilter && row.dataset.topic !== topicFilter) show = false;
        if (visitFilter && row.dataset.visit !== visitFilter) show = false;
        if (dateFilter === 'today' && rowDate !== today) show = false;
        if (dateFilter === 'week' && rowDate < weekAgo) show = false;
        if (dateFilter === 'month' && rowDate < monthAgo) show = false;
        if (searchText && !row.dataset.search.toLowerCase().includes(searchText)) show = false;
        
        row.style.display = show ? '' : 'none';
        if (show) visibleCount++;
    });
    
    const countEl = document.getElementById('appealsCount');
    if (countEl) countEl.innerText = visibleCount;
}

function resetFilters() {
    ['searchInput','statusFilter','topicFilter','needVisitFilter','dateFilter'].forEach(id => {
        const el = document.getElementById(id); if(el) el.value = '';
    });
    applyFilters();
}

let sortDirection = {};
function sortTable(colIndex) {
    const table = document.getElementById('appealsTable');
    if (!table) return;
    const tbody = table.querySelector('tbody');
    const rows = Array.from(tbody.querySelectorAll('tr'));
    
    sortDirection[colIndex] = sortDirection[colIndex] === 'asc' ? 'desc' : 'asc';
    const dir = sortDirection[colIndex];
    
    rows.sort((a, b) => {
        let aVal = a.cells[colIndex]?.innerText.trim() || '';
        let bVal = b.cells[colIndex]?.innerText.trim() || '';
        if (colIndex === 1) { aVal = a.dataset.date || ''; bVal = b.dataset.date || ''; }
        if (colIndex === 0 || colIndex === 1) {
            return dir === 'asc' ? aVal.localeCompare(bVal, undefined, {numeric: true}) : bVal.localeCompare(aVal, undefined, {numeric: true});
        }
        return dir === 'asc' ? aVal.localeCompare(bVal, 'ru') : bVal.localeCompare(aVal, 'ru');
    });
    rows.forEach(row => tbody.appendChild(row));
}

async function updateAppeal(appealId) {
    const statusEl = document.getElementById(`status_${appealId}`);
    const resultEl = document.getElementById(`result_${appealId}`);
    if (!statusEl || !resultEl) return;
    try {
        const response = await fetch(`/admin/update_appeal/${appealId}`, {
            method: 'POST', headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({status: statusEl.value, result_text: resultEl.value})
        });
        if (response.ok) { alert('Статус обновлен'); location.reload(); } 
        else alert('Ошибка обновления');
    } catch(e) { console.error(e); alert('Ошибка сети'); }
}

function showFullText(id, text) {
    const modal = document.getElementById('fullTextModal');
    const content = document.getElementById('fullTextContent');
    if (modal && content) { content.innerText = text; modal.style.display = 'flex'; }
}
function closeFullTextModal() {
    const modal = document.getElementById('fullTextModal');
    if (modal) modal.style.display = 'none';
}
document.addEventListener('click', (e) => {
    const modal = document.getElementById('fullTextModal');
    if (e.target === modal) closeFullTextModal();
});

function toggleApproval(appealId) {
    fetch(`/admin/appeal/${appealId}/toggle_approval`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' }
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            const badge = document.getElementById(`badge_${appealId}`);
            const btn = document.getElementById(`btn_approve_${appealId}`);
            
            badge.textContent = data.label;
            badge.className = `approval-badge ${data.is_approved ? 'approved' : 'pending'}`;
            btn.textContent = data.is_approved ? 'Скрыть' : 'Одобрить';
        } else {
            alert('Ошибка: ' + (data.error || 'Не удалось изменить статус'));
        }
    })
    .catch(err => {
        console.error('Ошибка запроса:', err);
        alert('Ошибка сети. Попробуйте позже.');
    });
}