(function() {
  // Natural sort for version strings (e.g., "4.18.0" < "4.19.0" < "5.0")
  function naturalSort(a, b) {
    var ax = [], bx = [];
    a.replace(/(\d+)|(\D+)/g, function(_, $1, $2) { ax.push([$1 || Infinity, $2 || '']); });
    b.replace(/(\d+)|(\D+)/g, function(_, $1, $2) { bx.push([$1 || Infinity, $2 || '']); });
    while (ax.length && bx.length) {
      var an = ax.shift();
      var bn = bx.shift();
      var nn = (an[0] - bn[0]) || an[1].localeCompare(bn[1]);
      if (nn) return nn;
    }
    return ax.length - bx.length;
  }

  // Populate filter dropdowns with unique values from the table
  function populateFilters() {
    var table = document.querySelector('#history-table tbody');
    if (!table) return;

    var ocpVersions = new Set();
    var tcoVersions = new Set();
    var hasNone = false;

    table.querySelectorAll('tr[data-ocp-version]').forEach(function(row) {
      var ocpVersion = row.getAttribute('data-ocp-version');
      var tcoVersion = row.getAttribute('data-tco-version');

      if (ocpVersion) ocpVersions.add(ocpVersion);
      if (tcoVersion) {
        if (tcoVersion === 'none') {
          hasNone = true;
        } else {
          tcoVersions.add(tcoVersion);
        }
      }
    });

    var ocpFilter = document.getElementById('ocp-filter');
    var tcoFilter = document.getElementById('tco-filter');

    if (ocpFilter) {
      Array.from(ocpVersions).sort(naturalSort).reverse().forEach(function(version) {
        var option = document.createElement('option');
        option.value = version;
        option.textContent = version;
        ocpFilter.appendChild(option);
      });
    }

    if (tcoFilter) {
      Array.from(tcoVersions).sort(naturalSort).reverse().forEach(function(version) {
        var option = document.createElement('option');
        option.value = version;
        option.textContent = version;
        tcoFilter.appendChild(option);
      });
      // Add "None" option if there are scans without TCO version
      if (hasNone) {
        var noneOption = document.createElement('option');
        noneOption.value = 'none';
        noneOption.textContent = 'None';
        tcoFilter.appendChild(noneOption);
      }
    }
  }

  // Initialize filters on page load
  setTimeout(populateFilters, 0);
})();

function filterHistoryTable() {
  var ocpFilter = document.getElementById('ocp-filter');
  var tcoFilter = document.getElementById('tco-filter');
  var table = document.querySelector('#history-table tbody');

  if (!table) return;

  var ocpValue = ocpFilter ? ocpFilter.value : '';
  var tcoValue = tcoFilter ? tcoFilter.value : '';

  var allRows = Array.from(table.querySelectorAll('tr'));
  var shown = 0;
  var total = 0;

  for (var i = 0; i < allRows.length; i++) {
    var row = allRows[i];

    // Skip detail rows in counting - they're controlled by their parent row
    if (row.classList.contains('detail-row')) {
      continue;
    }

    total++;

    var rowOcpVersion = row.getAttribute('data-ocp-version') || '';
    var rowTcoVersion = row.getAttribute('data-tco-version') || '';

    var matchOcp = !ocpValue || rowOcpVersion === ocpValue;
    var matchTco = !tcoValue || rowTcoVersion === tcoValue;

    var visible = matchOcp && matchTco;
    row.style.display = visible ? '' : 'none';

    // Also show/hide the associated detail row
    if (i + 1 < allRows.length && allRows[i + 1].classList.contains('detail-row')) {
      allRows[i + 1].style.display = visible ? '' : 'none';
    }

    if (visible) shown++;
  }

  var counts = document.getElementById('history-filter-counts');
  if (counts) {
    counts.textContent = shown === total ? '' : 'Showing ' + shown + ' of ' + total;
  }
}
