// Ensure DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    console.log('DOM fully loaded, initializing charts');

    let lightbox = document.querySelector('.chart-lightbox');
    if (!lightbox) {
        lightbox = document.createElement('div');
        lightbox.className = 'chart-lightbox';
        document.body.appendChild(lightbox);
    }

    const chartInstances = new Map();
    let isPrinting = false;

    const filteredNodeCards = document.getElementById('filteredNodeCards');
    const paginationContainer = document.getElementById('nodeCardPagination');

    if (filteredNodeCards && paginationContainer) {
        sortNodeCards(filteredNodeCards);
        paginateNodeCards(filteredNodeCards, paginationContainer, 5); // ✅ Pagination done here
    }

    // Utility: get color based on score
    function getScoreColor(score) {
        if (score < 40) return '#B71C1C';
        if (score < 70) return '#ffa000';
        return '#4CAF50';
    }

    // Utility: render line chart
    function renderLineChart(canvas, label, unit) {
        try {
            const ctx = canvas.getContext('2d');
            const data = JSON.parse(canvas.dataset.values || '[]');
            if (!data.length) throw new Error('Empty data');
            return new Chart(ctx, {
                type: 'line',
                data: {
                    labels: data.map(v => new Date(parseInt(v.timestamp)).toLocaleTimeString()),
                    datasets: [{
                        label: label,
                        data: data.map(v => v.value),
                        borderColor: '#0071FF',
                        backgroundColor: 'rgba(0, 113, 255, 0.1)',
                        fill: true,
                        tension: 0.4
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        y: { beginAtZero: true, title: { display: true, text: unit } },
                        x: { title: { display: true, text: 'Time (Last 24h)' } }
                    },
                    plugins: {
                        legend: { display: true },
                        tooltip: { mode: 'index', intersect: false }
                    }
                }
            });
        } catch (e) {
            console.error(`Failed to render line chart (${label}):`, e);
            canvas.insertAdjacentHTML('afterend', `<p class="warning">⚠️ Failed to render ${label}</p>`);
            return null;
        }
    }

    // Utility: setup zoom on chart
    function setupChartZoom(chartItem, canvas, chart, unit) {
        const originalParent = chartItem.parentElement;
        const nextSibling = chartItem.nextSibling;

        chartItem.setAttribute('aria-label', 'Click or press Enter to enlarge chart');
        chartItem.setAttribute('aria-expanded', 'false');
        chartItem.insertAdjacentHTML('afterbegin', '<span class="chart-zoom-icon material-icons">zoom_in</span>');

        let isZoomed = false;

        function enterZoom() {
            if (isZoomed || isPrinting) return;
            isZoomed = true;
            chartItem.classList.add('zoomed');
            chartItem.setAttribute('aria-expanded', 'true');
            lightbox.classList.add('active');
            lightbox.appendChild(chartItem);
            chart?.resize();
        }

        function exitZoom() {
            if (!isZoomed) return;
            isZoomed = false;
            chartItem.classList.remove('zoomed');
            chartItem.setAttribute('aria-expanded', 'false');
            lightbox.classList.remove('active');
            if (originalParent && originalParent.isConnected) {
                if (nextSibling && nextSibling.isConnected) {
                    originalParent.insertBefore(chartItem, nextSibling);
                } else {
                    originalParent.appendChild(chartItem);
                }
            }
            chart?.resize();
        }

        chartItem.addEventListener('click', e => {
            e.preventDefault();
            isZoomed ? exitZoom() : enterZoom();
        });

        lightbox.addEventListener('click', e => {
            if (e.target === lightbox) exitZoom();
        });

        document.addEventListener('keydown', e => {
            if (e.key === 'Escape' && lightbox.classList.contains('active')) {
                const zoomedChart = lightbox.querySelector('.chart-item.zoomed');
                if (zoomedChart) zoomedChart.click(); // triggers exitZoom
            }
        });


        chartItem.setAttribute('tabindex', '0');
        chartItem.addEventListener('keydown', e => {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                chartItem.click();
            }
        });
    }

    // Utility: initialize any chart by ID and config
    function initChart(canvasId, label, unit, type = 'line') {
        const canvas = document.getElementById(canvasId);
        if (!canvas) return;

        const chartItem = canvas.closest('.chart-item');
        let chart = null;

        if (type === 'line') {
            chart = renderLineChart(canvas, label, unit);
        } else if (type === 'doughnut') {
            try {
                const data = JSON.parse(canvas.dataset.values || '{}');
                if (!data.value) throw new Error('Missing value');

                chart = new Chart(canvas, {
                    type: 'doughnut',
                    data: {
                        labels: ['Nodes'],
                        datasets: [{
                            data: [data.value, Math.max(100 - data.value, 0)],
                            backgroundColor: ['#0071FF', '#E0E0E0'],
                            borderWidth: 0
                        }]
                    },
                    options: {
                        responsive: true,
                        cutout: '80%',
                        plugins: {
                            legend: { display: false },
                            tooltip: { enabled: false },
                            title: {
                                display: true,
                                text: `${data.value} Nodes`,
                                position: 'bottom',
                                font: { size: 16 }
                            }
                        }
                    }
                });
            } catch (e) {
                console.error(`Failed to render doughnut chart (${label}):`, e);
                canvas.insertAdjacentHTML('afterend', `<p class="warning">⚠️ Failed to render ${label}</p>`);
                return;
            }
        }

        if (chart && chartItem) {
            chartInstances.set(canvas, chart);
            setupChartZoom(chartItem, canvas, chart, unit);
        }
    }

    // Define charts to initialize
    const chartConfigs = [
        { id: 'clusterCpuChart', label: 'Cluster CPU Usage', unit: 'CPU Usage (%)' },
        { id: 'clusterMemChart', label: 'Cluster Memory Usage', unit: 'Memory Usage (%)' },
        { id: 'podCountChart', label: 'Total Pods', unit: 'Pod Count' },
        { id: 'restartChart', label: 'Pod Restarts', unit: 'Restarts' },
        { id: 'nodeCountChart', label: 'Node Count', unit: 'Node Count', type: 'doughnut' }
    ];

    chartConfigs.forEach(cfg => initChart(cfg.id, cfg.label, cfg.unit, cfg.type));

    // Node-level line charts
    document.querySelectorAll('canvas.node-chart').forEach(canvas => {
        const chartItem = canvas.closest('.chart-item');
        const label = chartItem?.querySelector('h3')?.textContent || 'Node Metric';
        const unit = /cpu|memory|disk/i.test(label) ? '%' : '';
        const chart = renderLineChart(canvas, label, unit);
        if (chart && chartItem) {
            chartInstances.set(canvas, chart);
            setupChartZoom(chartItem, canvas, chart, unit);
        }
    });

    // Sparklines (no zoom)
    document.querySelectorAll('.sparkline').forEach(canvas => {
        try {
            const values = JSON.parse(canvas.dataset.values || '[]');
            if (!values.length) return;
            new Chart(canvas, {
                type: 'line',
                data: {
                    labels: Array(values.length).fill(''),
                    datasets: [{
                        data: values,
                        borderColor: '#0071FF',
                        backgroundColor: 'rgba(0, 113, 255, 0.1)',
                        fill: true,
                        tension: 0.4
                    }]
                },
                options: {
                    responsive: true,
                    plugins: { legend: { display: false }, tooltip: { enabled: false } },
                    scales: { x: { display: false }, y: { display: false } }
                }
            });
        } catch (e) {
            console.error('Sparkline error:', e);
            canvas.insertAdjacentHTML('afterend', '<span class="warning">⚠️ Invalid sparkline data</span>');
        }
    });

    // Score bar animation
    document.querySelectorAll('.progress-bar').forEach(bar => {
        let score = parseFloat(bar.style.getPropertyValue('--cluster-score')) || 0;

        if (score === 0) {
            const scoreText = bar.closest('section')?.textContent.match(/Score: (\d+)/)?.[1];
            score = parseFloat(scoreText) || 0;
        }

        const progress = bar.querySelector('.progress');
        const dot = bar.querySelector('.pulse-dot');
        const color = getScoreColor(score);

        requestAnimationFrame(() => {
            progress.style.width = `${score}%`;
            progress.style.background = color;
            if (dot) {
                dot.style.left = `${score - 4}%`;
                dot.style.display = 'block';
                dot.style.background = color;
                dot.style.border = `4px solid ${color}`;
                dot.style.opacity = '1';
            }
        });
    });

    document.querySelectorAll('.status-chip').forEach(chip => {
        const section = chip.closest('section');
        let score = parseFloat(chip.style.getPropertyValue('--cluster-score')) || 0;

        if (score === 0) {
            const scoreText = section?.textContent.match(/Score: (\d+)/)?.[1];
            score = parseFloat(scoreText) || 0;
        }

        const color = getScoreColor(score);
        chip.style.backgroundColor = color;
    });


    // Status Count-Up Animation for Passed/Failed
    document.querySelectorAll('.count-up').forEach(el => {
        const target = parseInt(el.getAttribute('data-count'), 10);
        if (!isNaN(target)) {
            let start = 0;
            const duration = 1500;
            const increment = target / (duration / 16);

            const timer = setInterval(() => {
                start += increment;
                if (start >= target) {
                    start = target;
                    clearInterval(timer);
                }
                el.textContent = Math.round(start);
            }, 16);
        }
    });

    // Tab switching
    const tabs = document.querySelectorAll('.tabs li');
    const tabContents = document.querySelectorAll('.tab-content');

    tabs.forEach(tab => {
        tab.addEventListener('click', () => {
            tabs.forEach(t => t.classList.remove('active'));
            tabContents.forEach(tc => tc.classList.remove('active'));
            tab.classList.add('active');
            const target = tab.getAttribute('data-tab');
            const content = document.getElementById(target);
            content?.classList.add('active');
        });
    });

    // Drawer links to tabs
    document.querySelectorAll('#navDrawer .nav-item a').forEach(link => {
        link.addEventListener('click', e => {
            e.preventDefault();
            const target = link.getAttribute('href')?.replace('#', '');
            const tab = document.querySelector(`.tabs li[data-tab="${target}"]`);
            if (tab) tab.click();
            document.getElementById('navDrawer')?.classList.remove('open');
            document.getElementById('navScrim')?.classList.remove('open');
            document.body.style.overflow = '';
        });
    });

    function sortNodeCards(container) {
        const cards = Array.from(container.querySelectorAll('.collapsible-container'));

        const getStatusRank = card => {
            const badgeClasses = Array.from(card.querySelectorAll('.metric-badge')).map(b => b.className);
            if (badgeClasses.some(cls => cls.includes('critical'))) return 0;
            if (badgeClasses.some(cls => cls.includes('warning'))) return 1;
            return 2; // normal or unknown
        };

        cards.sort((a, b) => {
            const aRank = getStatusRank(a);
            const bRank = getStatusRank(b);
            if (aRank !== bRank) return aRank - bRank;

            const nameA = a.querySelector('.node-name')?.textContent.trim().toLowerCase() || '';
            const nameB = b.querySelector('.node-name')?.textContent.trim().toLowerCase() || '';
            return nameA.localeCompare(nameB);
        });

        // Re-append in sorted order
        cards.forEach(card => container.appendChild(card));
    }

    // Toggle summary text (e.g., Show Findings ↔ Hide Findings)
    document.querySelectorAll('.collapsible-container > details > summary').forEach(summary => {
        const isRich = summary.querySelector('.summary-inner'); // skip rich custom ones
        if (isRich) return;

        const originalText = summary.textContent.trim();
        const openText = originalText.replace(/^Show/i, 'Hide');

        summary.addEventListener('click', () => {
            requestAnimationFrame(() => {
                const details = summary.parentElement;
                if (!details || !details.tagName === 'DETAILS') return;

                if (details.open) {
                    summary.textContent = openText;
                } else {
                    summary.textContent = originalText;
                }
            });
        });
    });

    // PDF Export Button
    // hide your “chrome” before-and-after
    function togglePrintMode(on) {
        document.querySelectorAll('#savePdfBtn, .table-pagination, #menuFab, #backToTop')
            .forEach(el => el.style.display = on ? 'none' : '');
    }

    savePdfBtn.addEventListener('click', () => {
        isPrinting = true;

        // 1) expand all details and show every tab
        const detailsStates = [];
        document.querySelectorAll('details').forEach(d => {
            detailsStates.push({ el: d, open: d.open });
            d.open = true;
        });
        // reveal every tab’s content
        document.querySelectorAll('.tab-content').forEach(tc => tc.classList.add('active'));

        // 2) hide UI chrome
        togglePrintMode(true);

        // 3) render HTML -> PDF
        const pdf = new jsPDF('p', 'mm', 'a4');
        pdf.html(
            document.querySelector('.wrapper'),
            {
                html2canvas: { scale: 2 },
                callback: () => {
                    pdf.save('kubebuddy_report.pdf');

                    // 4) restore everything
                    togglePrintMode(false);
                    detailsStates.forEach(d => d.el.open = d.open);
                    // put tabs back to the one the user had open
                    // (optional: track which tab was active and restore)
                    isPrinting = false;
                },
                margin: [10, 10, 10, 10],
                autoPaging: true
            }
        );
    });

    // Initialize pagination on page load for all open collapsibles
    document.querySelectorAll('.collapsible-container > details[open]').forEach(details => {
        const container = details.parentElement;
        paginateTable(container);
    });
    document.querySelectorAll('.collapsible-container > details').forEach(details => {
        const container = details.parentElement;
        details.addEventListener('toggle', () => {
            if (details.open) {
                setTimeout(() => paginateTable(container), 100); // short delay ensures content is fully visible
            }
        });
    });
    // Add Filtering Support
    const nodeFilterInput = document.getElementById('nodeFilterInput');


    if (nodeFilterInput && filteredNodeCards) {
        const originalCards = Array.from(filteredNodeCards.children);

        function debounce(fn, delay) {
            let timeout;
            return (...args) => {
                clearTimeout(timeout);
                timeout = setTimeout(() => fn(...args), delay);
            };
        }

        nodeFilterInput.addEventListener('input', debounce(() => {
            const query = nodeFilterInput.value.toLowerCase();
            filteredNodeCards.innerHTML = '';
            let matchFound = false;

            originalCards.forEach(card => {
                if (card.textContent.toLowerCase().includes(query)) {
                    const clone = card.cloneNode(true);
                    const originalCanvases = card.querySelectorAll('canvas.node-chart');
                    const clonedCanvases = clone.querySelectorAll('canvas.node-chart');

                    originalCanvases.forEach((orig, i) => {
                        const val = orig.dataset.values;
                        const newCanvas = document.createElement('canvas');
                        newCanvas.className = 'node-chart';
                        newCanvas.dataset.values = val;
                        const oldCanvas = clonedCanvases[i];
                        if (oldCanvas && oldCanvas.parentNode) {
                            oldCanvas.parentNode.replaceChild(newCanvas, oldCanvas);
                        }
                    });

                    filteredNodeCards.appendChild(clone);
                    matchFound = true;
                }
            });

            if (!matchFound) {
                filteredNodeCards.innerHTML = "<p style='padding: 10px;'>🚫 No matching nodes found.</p>";
            }

            if (matchFound) {
                sortNodeCards(filteredNodeCards);
                paginateNodeCards(filteredNodeCards, paginationContainer, 5);

            }

            filteredNodeCards.querySelectorAll('canvas.node-chart').forEach(canvas => {
                const chartItem = canvas.closest('.chart-item');
                const label = chartItem?.querySelector('h3')?.textContent || 'Node Metric';
                const unit = /cpu|memory|disk/i.test(label) ? '%' : '';
                const chart = renderLineChart(canvas, label, unit);
                if (chart && chartItem) {
                    setupChartZoom(chartItem, canvas, chart, unit);
                }
            });
        }, 300));
    }
});

// Add Sorting Function
function sortTable(container, columnIndex) {
    const table = container.querySelector('table');
    if (!table) return;

    const rows = Array.from(table.querySelectorAll('tr')).filter(r => r.cells.length > 0);
    const header = rows.find(r => r.querySelector('th'));
    const dataRows = header ? rows.filter(r => r !== header) : rows;

    const ascending = container.sortState?.columnIndex === columnIndex ? !container.sortState.ascending : true;
    container.sortState = { columnIndex, ascending };

    dataRows.sort((a, b) => {
        const valA = a.cells[columnIndex].textContent.trim();
        const valB = b.cells[columnIndex].textContent.trim();

        const isNumeric = !isNaN(parseFloat(valA)) && !isNaN(parseFloat(valB));
        return ascending
            ? isNumeric ? valA - valB : valA.localeCompare(valB)
            : isNumeric ? valB - valA : valB.localeCompare(valA);
    });

    const tbody = table.querySelector('tbody') || table;
    dataRows.forEach(row => tbody.appendChild(row));
}

function paginateNodeCards(container, paginationContainer, initialItemsPerPage = 5) {
    const cards = Array.from(container.querySelectorAll('.collapsible-container'));
    let itemsPerPage = initialItemsPerPage;
    let currentPage = 1;

    const totalPages = () => Math.ceil(cards.length / itemsPerPage);

    function showPage() {
        const start = (currentPage - 1) * itemsPerPage;
        const end = start + itemsPerPage;
        cards.forEach((card, i) => {
            card.style.display = (i >= start && i < end) ? '' : 'none';
        });
    }

    function createButton(label, onClick, disabled = false, active = false) {
        const btn = document.createElement('button');
        btn.textContent = label;
        if (active) btn.classList.add('active');
        btn.disabled = disabled;
        btn.addEventListener('click', onClick);
        return btn;
    }

    function updateControls() {
        paginationContainer.innerHTML = '';

        // Prev
        paginationContainer.appendChild(
            createButton('←', () => { currentPage--; update(); }, currentPage === 1)
        );

        // Page-number buttons
        for (let i = 1; i <= totalPages(); i++) {
            paginationContainer.appendChild(
                createButton(i, () => { currentPage = i; update(); }, false, i === currentPage)
            );
        }

        // Next
        paginationContainer.appendChild(
            createButton('→', () => { currentPage++; update(); }, currentPage === totalPages())
        );

        // **Items-per-page selector**
        const selector = document.createElement('select');
        [5, 10, 25, 50].forEach(n => {
            const opt = document.createElement('option');
            opt.value = n;
            opt.textContent = `${n} per page`;
            if (n === itemsPerPage) opt.selected = true;
            selector.appendChild(opt);
        });
        selector.addEventListener('change', () => {
            itemsPerPage = parseInt(selector.value, 10);
            currentPage = 1;
            update();
        });

        paginationContainer.appendChild(selector);
    }

    function update() {
        showPage();
        updateControls();
    }

    // kick it off
    update();
}

function paginateTable(collapsibleContainer) {
    const table = collapsibleContainer.querySelector('table');
    if (!table) return;

    const allRows = Array.from(table.querySelectorAll('tr')).filter(r => r.cells.length > 0);
    const headerRow = allRows.find(row => row.querySelector('th'));
    const dataRows = headerRow ? allRows.filter(row => row !== headerRow) : allRows;

    if (dataRows.length <= 10) {
        allRows.forEach(r => r.style.display = '');
        collapsibleContainer.querySelector('.table-pagination')?.remove();
        return;
    }

    let currentPage = 1;
    let pageSize = 10;
    const maxVisiblePages = 5;

    const totalPages = () => Math.ceil(dataRows.length / pageSize);

    function showPage() {
        if (headerRow) headerRow.style.display = '';
        const start = (currentPage - 1) * pageSize;
        const end = start + pageSize;
        dataRows.forEach((row, i) => {
            row.style.display = (i >= start && i < end) ? '' : 'none';
        });
    }

    function createButton(label, onClick, disabled = false, active = false) {
        const btn = document.createElement('button');
        btn.textContent = label;
        if (active) btn.classList.add('active');
        btn.disabled = disabled;
        btn.addEventListener('click', onClick);
        return btn;
    }

    function createEllipsis() {
        const span = document.createElement('span');
        span.textContent = '...';
        span.className = 'pagination-ellipsis';
        return span;
    }

    function updateControls() {
        let pagination = collapsibleContainer.querySelector('.table-pagination');
        if (!pagination) {
            pagination = document.createElement('div');
            pagination.className = 'table-pagination';
            collapsibleContainer.appendChild(pagination);
        }

        pagination.innerHTML = '';

        // Prev
        pagination.appendChild(createButton('←', () => {
            if (currentPage > 1) {
                currentPage--;
                update();
            }
        }, currentPage === 1));

        const total = totalPages();
        let startPage = Math.max(1, currentPage - Math.floor(maxVisiblePages / 2));
        let endPage = Math.min(total, startPage + maxVisiblePages - 1);

        if (endPage - startPage < maxVisiblePages - 1) {
            startPage = Math.max(1, endPage - maxVisiblePages + 1);
        }

        if (startPage > 1) {
            pagination.appendChild(createButton('1', () => {
                currentPage = 1;
                update();
            }));
            if (startPage > 2) {
                pagination.appendChild(createEllipsis());
            }
        }

        for (let i = startPage; i <= endPage; i++) {
            pagination.appendChild(createButton(i, () => {
                currentPage = i;
                update();
            }, false, i === currentPage));
        }

        if (endPage < total) {
            if (endPage < total - 1) {
                pagination.appendChild(createEllipsis());
            }
            pagination.appendChild(createButton(total, () => {
                currentPage = total;
                update();
            }));
        }

        // Next
        pagination.appendChild(createButton('→', () => {
            if (currentPage < total) {
                currentPage++;
                update();
            }
        }, currentPage === total));

        // Page size selector
        const selector = document.createElement('select');
        [10, 25, 50].forEach(n => {
            const opt = document.createElement('option');
            opt.value = n;
            opt.textContent = `${n} per page`;
            if (n === pageSize) opt.selected = true;
            selector.appendChild(opt);
        });
        selector.addEventListener('change', () => {
            pageSize = parseInt(selector.value, 10);
            currentPage = 1;
            update();
        });
        pagination.appendChild(selector);
    }

    function update() {
        showPage();
        updateControls();
    }

    update();
}
