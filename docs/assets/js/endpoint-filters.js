// Search + status filters for the Endpoints page.
// Mirrors filters.js from the Operators page: a text search over endpoint
// rows, status chips backed by each row's data-status attribute, and
// hash-based state (#status=<chip>&q=<term>) so filtered views are
// shareable. Operator groups whose rows are all hidden collapse too.

function parseEndpointHash() {
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

var currentEndpointFilter = 'all';

function updateEndpointHash() {
  var params = [];
  if (currentEndpointFilter !== 'all') params.push('status=' + currentEndpointFilter);
  var search = document.getElementById('endpoint-search');
  if (search && search.value) params.push('q=' + encodeURIComponent(search.value));
  history.replaceState(null, '', params.length ? '#' + params.join('&') : location.pathname);
}

function applyEndpointChipState() {
  document.querySelectorAll('.filter-btn').forEach(function(b) {
    b.classList.remove('active');
    b.setAttribute('aria-pressed', 'false');
  });
  var btn = document.querySelector('[data-filter="' + currentEndpointFilter + '"]');
  if (btn) { btn.classList.add('active'); btn.setAttribute('aria-pressed', 'true'); }
}

function setEndpointStatusFilter(filter) {
  currentEndpointFilter = filter;
  applyEndpointChipState();
  filterEndpointTable();
}

function filterEndpointTable() {
  var searchEl = document.getElementById('endpoint-search');
  var search = searchEl ? searchEl.value.toLowerCase() : '';
  var shown = 0, total = 0;

  document.querySelectorAll('.operator-group').forEach(function(group) {
    var groupShown = 0;
    group.querySelectorAll('tbody tr').forEach(function(row) {
      // Detail rows follow their parent row and share its visibility.
      if (row.classList.contains('detail-row')) return;
      total++;
      var status = (row.getAttribute('data-status') || '').toLowerCase();
      var text = row.textContent.toLowerCase();
      var visible = (!search || text.indexOf(search) !== -1) &&
        (currentEndpointFilter === 'all' || status === currentEndpointFilter);
      row.style.display = visible ? '' : 'none';
      var detail = row.nextElementSibling;
      if (detail && detail.classList.contains('detail-row')) {
        detail.style.display = visible ? '' : 'none';
      }
      if (visible) { shown++; groupShown++; }
    });
    group.style.display = groupShown === 0 ? 'none' : '';
  });

  var counts = document.getElementById('endpoint-filter-counts');
  if (counts) counts.textContent = shown === total ? '' : 'Showing ' + shown + ' of ' + total;
  updateEndpointHash();
}

(function() {
  var h = parseEndpointHash();
  if (h.status) { currentEndpointFilter = h.status; }
  if (h.q) {
    var searchEl = document.getElementById('endpoint-search');
    if (searchEl) searchEl.value = h.q;
  }
  setTimeout(function() {
    // Ignore status values that have no chip on this page.
    if (!document.querySelector('[data-filter="' + currentEndpointFilter + '"]')) {
      currentEndpointFilter = 'all';
    }
    applyEndpointChipState();
    filterEndpointTable();
  }, 0);
})();
