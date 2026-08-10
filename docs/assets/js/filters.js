function parseHash() {
  var hash = location.hash.slice(1);
  if (!hash) return {};
  var result = {};
  hash.split('&').forEach(function(part) {
    var idx = part.indexOf('=');
    if (idx === -1) return;
    result[part.slice(0, idx)] = decodeURIComponent(part.slice(idx + 1));
  });
  return result;
}

var currentFilter = 'all';

function updateHash() {
  var params = [];
  if (currentFilter !== 'all') params.push('status=' + currentFilter);
  var search = document.getElementById('table-search');
  if (search && search.value) params.push('q=' + encodeURIComponent(search.value));
  history.replaceState(null, '', params.length ? '#' + params.join('&') : location.pathname);
}

function setStatusFilter(filter) {
  currentFilter = filter;
  document.querySelectorAll('.filter-btn').forEach(function(b) {
    b.classList.remove('active');
    b.setAttribute('aria-pressed', 'false');
  });
  var btn = document.querySelector('[data-filter="' + filter + '"]');
  if (btn) { btn.classList.add('active'); btn.setAttribute('aria-pressed', 'true'); }
  filterTable();
}

function filterTable() {
  var searchEl = document.getElementById('table-search');
  var search = searchEl ? searchEl.value.toLowerCase() : '';
  var table = document.getElementById('operator-table');
  if (!table) return;
  var rows = table.querySelectorAll('tbody tr');
  var shown = 0, total = rows.length;
  rows.forEach(function(row) {
    var status = (row.getAttribute('data-status') || '').toLowerCase();
    var text = row.textContent.toLowerCase();
    var matchSearch = !search || text.indexOf(search) !== -1;
    var matchFilter = currentFilter === 'all' || status === currentFilter.toLowerCase();
    var visible = matchSearch && matchFilter;
    row.style.display = visible ? '' : 'none';
    if (visible) shown++;
  });
  var counts = document.getElementById('filter-counts');
  if (counts) counts.textContent = shown === total ? '' : 'Showing ' + shown + ' of ' + total;
  updateHash();
}

(function() {
  var h = parseHash();
  if (h.status) { currentFilter = h.status; }
  if (h.q) {
    var searchEl = document.getElementById('table-search');
    if (searchEl) searchEl.value = h.q;
  }
  setTimeout(function() { filterTable(); }, 0);
})();
