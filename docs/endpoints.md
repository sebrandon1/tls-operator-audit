---
layout: default
title: "Endpoints"
---

{% assign data = site.data.scan-results %}

{% include scan-info.html
   scan_date=data.scan_date
   cluster=data.cluster
   ocp_version=data.ocp_version
   tco_version=data.tco_version %}

<div class="summary-cards">
  <div class="card" data-tooltip="All discovered endpoints across operators">
    <div class="card-number">{{ data.summary.total_endpoints }}</div>
    <div class="card-label">Total Endpoints</div>
  </div>
  <div class="card card-pass" data-tooltip="Endpoints supporting ML-KEM key exchange">
    <div class="card-number">{{ data.summary.mlkem_endpoints }}</div>
    <div class="card-label">ML-KEM Endpoints</div>
  </div>
  <div class="card card-accent" data-tooltip="Percentage of endpoints with ML-KEM support">
    <div class="card-number">{{ data.summary.mlkem_percent }}%</div>
    <div class="card-label">ML-KEM Coverage</div>
  </div>
</div>

<h2>Endpoints by Operator</h2>

<div class="filter-bar">
  <input type="text" id="endpoint-search" placeholder="Search endpoints..." oninput="filterEndpointTable()" aria-label="Search endpoints">
  <div class="filter-buttons">
    <button class="filter-btn active" data-filter="all" onclick="setEndpointStatusFilter('all')" aria-pressed="true" data-tooltip="Show all endpoints">All</button>
    <button class="filter-btn" data-filter="compliant" onclick="setEndpointStatusFilter('compliant')" aria-pressed="false" data-tooltip="Show compliant endpoints only">Compliant</button>
    <button class="filter-btn" data-filter="closed" onclick="setEndpointStatusFilter('closed')" aria-pressed="false" data-tooltip="Show endpoints whose port is not accepting connections">Closed</button>
    <button class="filter-btn" data-filter="timeout" onclick="setEndpointStatusFilter('timeout')" aria-pressed="false" data-tooltip="Show endpoints that timed out during scanning">Timeout</button>
    <button class="filter-btn" data-filter="other" onclick="setEndpointStatusFilter('other')" aria-pressed="false" data-tooltip="Show endpoints with other non-compliant statuses">Other</button>
  </div>
  <span id="endpoint-filter-counts"></span>
</div>

{% for op in data.operators %}
{% if op.endpoints.size > 0 %}
<div class="operator-group">
  <details{% if op.endpoints.size <= 5 %} open{% endif %}>
    <summary>
      {{ op.name }}
      <span class="operator-group-meta">
        <span>{{ op.reachable_endpoints }} reachable</span>
        {% if op.closed_endpoints > 0 %}<span>{{ op.closed_endpoints }} closed</span>{% endif %}
        <span>{{ op.mlkem_percent }}% ML-KEM</span>
        {% include status-badge.html status=op.status %}
      </span>
    </summary>
    {% include endpoint-table.html endpoints=op.endpoints %}
  </details>
</div>
{% endif %}
{% endfor %}

<script src="{{ '/assets/js/endpoint-filters.js' | relative_url }}"></script>
