(function() {
  document.querySelectorAll('th.sortable').forEach(function(th) {
    th.setAttribute('aria-sort', 'none');
    th.addEventListener('click', function() {
      var table = th.closest('table');
      var tbody = table.querySelector('tbody');
      if (!tbody) return;
      var colIndex = Array.prototype.indexOf.call(th.parentNode.children, th);
      var dataType = th.getAttribute('data-type') || 'text';
      var asc = !th.classList.contains('sort-asc');
      table.querySelectorAll('th.sortable').forEach(function(h) {
        h.classList.remove('sort-asc', 'sort-desc');
        h.setAttribute('aria-sort', 'none');
      });
      th.classList.add(asc ? 'sort-asc' : 'sort-desc');
      th.setAttribute('aria-sort', asc ? 'ascending' : 'descending');

      var allRows = Array.from(tbody.querySelectorAll('tr'));
      var groups = [];
      allRows.forEach(function(row) {
        if (row.classList.contains('detail-row')) {
          if (groups.length) groups[groups.length - 1].push(row);
        } else {
          groups.push([row]);
        }
      });

      groups.sort(function(a, b) {
        var aCell = a[0].cells[colIndex];
        var bCell = b[0].cells[colIndex];
        if (!aCell || !bCell) return 0;
        var aVal = (aCell.getAttribute('data-sort') || aCell.textContent).trim();
        var bVal = (bCell.getAttribute('data-sort') || bCell.textContent).trim();
        if (dataType === 'number') {
          return (asc ? 1 : -1) * ((parseFloat(aVal) || 0) - (parseFloat(bVal) || 0));
        }
        return (asc ? 1 : -1) * aVal.localeCompare(bVal);
      });

      groups.forEach(function(group) {
        group.forEach(function(row) { tbody.appendChild(row); });
      });
    });
  });
})();
