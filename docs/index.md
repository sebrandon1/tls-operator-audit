---
layout: default
title: "Dashboard"
---

{% assign data = site.data.scan-results %}

{% include scan-info.html data=data %}

<div class="summary-cards">
  <div class="card" data-tooltip="Total operators scanned">
    <div class="card-number">{{ data.summary.total_operators }}</div>
    <div class="card-label">Operators</div>
  </div>
  <div class="card card-pass" data-tooltip="Operators with all endpoints supporting ML-KEM">
    <div class="card-number">{{ data.summary.pass }}</div>
    <div class="card-label">Pass</div>
  </div>
  <div class="card card-partial" data-tooltip="Operators with some or no ML-KEM support">
    <div class="card-number">{{ data.summary.partial | plus: data.summary.none }}</div>
    <div class="card-label">Partial / None</div>
  </div>
  <div class="card card-error" data-tooltip="Operators that encountered scan errors">
    <div class="card-number">{{ data.summary.error }}</div>
    <div class="card-label">Error</div>
  </div>
</div>

<div class="progress-container">
  <div class="progress-bar">
    <div class="progress-fill" style="width: {{ data.summary.mlkem_percent }}%"></div>
  </div>
  <span class="progress-label">{{ data.summary.mlkem_percent }}% ML-KEM ({{ data.summary.mlkem_endpoints }}/{{ data.summary.total_endpoints }} endpoints)</span>
</div>

<h2>Operators</h2>

<div class="filter-bar">
  <input type="text" id="table-search" placeholder="Search operators..." oninput="filterTable()" aria-label="Search operators">
  <div class="filter-buttons">
    <button class="filter-btn active" data-filter="all" onclick="setStatusFilter('all')" aria-pressed="true" data-tooltip="Show all operators">All</button>
    <button class="filter-btn" data-filter="pass" onclick="setStatusFilter('pass')" aria-pressed="false" data-tooltip="Show passing operators only">Pass</button>
    <button class="filter-btn" data-filter="partial" onclick="setStatusFilter('partial')" aria-pressed="false" data-tooltip="Show partially compliant operators">Partial</button>
    <button class="filter-btn" data-filter="none" onclick="setStatusFilter('none')" aria-pressed="false" data-tooltip="Show non-compliant operators">None</button>
    <button class="filter-btn" data-filter="error" onclick="setStatusFilter('error')" aria-pressed="false" data-tooltip="Show operators with scan errors">Error</button>
  </div>
  <span id="filter-counts"></span>
</div>

<div class="table-responsive">
<table class="data-table" id="operator-table">
  <thead>
    <tr>
      <th class="sortable">Operator</th>
      <th class="sortable">Version</th>
      <th class="sortable" data-tooltip="Jira tracking issue">Jira</th>
      <th class="sortable" data-tooltip="Operator catalog source">Catalog</th>
      <th class="sortable" data-type="number" data-tooltip="Reachable endpoint count">Endpoints</th>
      <th class="sortable" data-tooltip="ML-KEM supporting endpoints / total reachable">ML-KEM</th>
      <th class="sortable">Status</th>
    </tr>
  </thead>
  <tbody>
    {% for op in data.operators %}
    <tr data-status="{{ op.status | downcase }}">
      <td><a href="{{ '/operators/' | append: op.name | relative_url }}">{{ op.name }}</a></td>
      <td>{% if op.version and op.version != "" %}{{ op.version }}{% else %}&mdash;{% endif %}</td>
      <td><a href="https://redhat.atlassian.net/browse/{{ op.jira }}" target="_blank" rel="noopener">{{ op.jira }}</a></td>
      <td>{{ op.catalog }}</td>
      <td data-sort="{{ op.reachable_endpoints }}">
        {% if op.closed_endpoints > 0 %}
          {{ op.reachable_endpoints }} reachable ({{ op.closed_endpoints }} closed)
        {% elsif op.total_endpoints > 0 %}
          {{ op.reachable_endpoints }}
        {% else %}
          -
        {% endif %}
      </td>
      <td>
        {% if op.reachable_endpoints > 0 %}
          {{ op.mlkem_endpoints }}/{{ op.reachable_endpoints }}
        {% else %}
          -
        {% endif %}
      </td>
      <td>{% include status-badge.html status=op.status %}</td>
    </tr>
    {% endfor %}
  </tbody>
</table>
</div>
