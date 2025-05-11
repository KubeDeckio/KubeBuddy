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

    // Navigation Drawer
    const navDrawer = document.getElementById('navDrawer');
    const navToggle = document.getElementById('menuFab');
    const navClose = document.getElementById('navClose');
    const navScrim = document.getElementById('navScrim');
    const menuBtn = document.getElementById('menuFab');
    const menuIcon = document.getElementById('menuIcon');


    function toggleDrawer() {
        const isOpen = navDrawer.classList.contains('open');
        navDrawer.classList.toggle('open');
        navScrim.classList.toggle('open');
        menuBtn.classList.toggle('open');
        menuIcon.textContent = isOpen ? 'menu' : 'close';
        if (window.innerWidth <= 800) {
            document.body.style.overflow = isOpen ? '' : 'hidden';
        }
    }

    navToggle.addEventListener('click', toggleDrawer);
    navClose.addEventListener('click', toggleDrawer);
    navScrim.addEventListener('click', toggleDrawer);

    // Populate drawer with the same tabs you have up in the header
    const tabList = document.querySelectorAll('.header .tabs li');
    const navItemsContainer = document.querySelector('#navDrawer .nav-items');

    if (navItemsContainer) {
        // clear any placeholder
        navItemsContainer.innerHTML = '';

        tabList.forEach(tab => {
            const target = tab.getAttribute('data-tab');
            const li = document.createElement('li');
            li.className = 'nav-item';

            const a = document.createElement('a');
            a.href = `#${target}`;
            a.textContent = tab.textContent.trim();

            a.addEventListener('click', e => {
                e.preventDefault();
                // switch to that tab
                const headerTab = document.querySelector(`.tabs li[data-tab="${target}"]`);
                if (headerTab) headerTab.click();
                // close drawer
                toggleDrawer();
            });

            li.appendChild(a);
            navItemsContainer.appendChild(li);
        });
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

    // Wire up metric-card clicks instead of inline onclicks
    document.querySelectorAll('.metric-card[data-tab]').forEach(card => {
        card.style.cursor = 'pointer';
        card.addEventListener('click', () => {
            const target = card.dataset.tab;
            const tab = document.querySelector(`.tabs li[data-tab="${target}"]`);
            if (tab) tab.click();
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
        originalCards = Array.from(filteredNodeCards.children);
        nodeFilterInput.addEventListener('input', () => {
            const searchTerm = nodeFilterInput.value.toLowerCase();
            const filteredCards = originalCards.filter(card => {
                const nodeName = card.querySelector('.node-name')?.textContent.toLowerCase() || '';
                const metrics = Array.from(card.querySelectorAll('.metric-badge')).map(badge => badge.textContent.toLowerCase()).join(' ');
                return nodeName.includes(searchTerm) || metrics.includes(searchTerm);
            });
            // Clear and re-add filtered cards
            filteredNodeCards.innerHTML = '';
            filteredCards.forEach(card => filteredNodeCards.appendChild(card));
            paginateNodeCards(filteredNodeCards, paginationContainer, 5); // Reset pagination
        });
    }


    function paginateNodeCards(container, pagination, pageSize) {
        if (!container || !pagination) return;

        let currentPage = 1;
        const cards = Array.from(container.children);

        function totalPages() {
            return Math.ceil(cards.length / pageSize);
        }

        function showPage() {
            const start = (currentPage - 1) * pageSize;
            const end = start + pageSize;

            cards.forEach((card, index) => {
                card.style.display = (index >= start && index < end) ? '' : 'none';
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
            pagination.innerHTML = '';

            // Prev
            pagination.appendChild(
                createButton('←', () => {
                    currentPage--;
                    update();
                }, currentPage === 1)
            );

            // Page-number buttons
            for (let i = 1; i <= totalPages(); i++) {
                pagination.appendChild(
                    createButton(i, () => {
                        currentPage = i;
                        update();
                    }, false, i === currentPage)
                );
            }

            // Ellipsis and last page button if needed
            if (totalPages() > 5 && currentPage < totalPages() - 2) {
                if (currentPage < totalPages() - 3) {
                    pagination.appendChild(createEllipsis());
                }
                pagination.appendChild(createButton(totalPages(), () => {
                    currentPage = totalPages();
                    update();
                }));
            }

            // Next
            pagination.appendChild(
                createButton('→', () => {
                    if (currentPage < totalPages()) {
                        currentPage++;
                        update();
                    }
                }, currentPage === totalPages())
            );

            // Page size selector
            const selector = document.createElement('select');
            [5, 10, 25, 50].forEach(n => {
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

        function createEllipsis() {
            const span = document.createElement('span');
            span.textContent = '...';
            return span;
        }

        function update() {
            showPage();
            updateControls();
        }

        update();
    }


    function paginateTable(container) {
        if (!container) return;

        const table = container.querySelector('table');
        if (!table) return;

        const rows = Array.from(table.querySelectorAll('tbody tr'));
        const paginationContainer = container.querySelector('.table-pagination');
        if (paginationContainer) {
            paginationContainer.remove();
        }
        const newPaginationContainer = document.createElement('div');
        newPaginationContainer.className = 'table-pagination';
        container.appendChild(newPaginationContainer);

        const pageSize = 5;
        let currentPage = 1;

        function totalPages() {
            return Math.ceil(rows.length / pageSize);
        }

        function showPage() {
            const start = (currentPage - 1) * pageSize;
            const end = start + pageSize;

            rows.forEach((row, index) => {
                row.style.display = (index >= start && index < end) ? '' : 'none';
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
            newPaginationContainer.innerHTML = '';

            // Prev
            newPaginationContainer.appendChild(
                createButton('←', () => {
                    currentPage--;
                    update();
                }, currentPage === 1)
            );

            // Page-number buttons
            for (let i = 1; i <= totalPages(); i++) {
                newPaginationContainer.appendChild(
                    createButton(i, () => {
                        currentPage = i;
                        update();
                    }, false, i === currentPage)
                );
            }

            if (totalPages() > 5 && currentPage < totalPages() - 2) {
                if (currentPage < totalPages() - 3) {
                    newPaginationContainer.appendChild(createEllipsis());
                }
                newPaginationContainer.appendChild(createButton(totalPages(), () => {
                    currentPage = totalPages();
                    update();
                }));
            }

            // Next
            newPaginationContainer.appendChild(
                createButton('→', () => {
                    if (currentPage < totalPages()) {
                        currentPage++;
                        update();
                    }
                }, currentPage === totalPages())
            );

            // Page size selector
            const selector = document.createElement('select');
            [5, 10, 25, 50].forEach(n => {
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
            newPaginationContainer.appendChild(selector);
        }

        function createEllipsis() {
            const span = document.createElement('span');
            span.textContent = '...';
            return span;
        }

        function update() {
            showPage();
            updateControls();
        }

        update();
    }
});    