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
    window.addEventListener('scroll', () => {
        const button = document.getElementById('backToTop');
        if (button) button.style.display = window.scrollY > 200 ? 'block' : 'none';
    });

    // Global print state
    let isPrinting = false;

    function getScoreColor(score) {
        if (score < 40) return '#B71C1C';
        if (score < 70) return '#ffa000';
        return '#4CAF50';
    }

    const filteredNodeCards = document.getElementById('filteredNodeCards');
    const paginationContainer = document.getElementById('nodeCardPagination');
    const nodeFilterInput = document.getElementById('nodeFilterInput');

    if (filteredNodeCards && paginationContainer) {
        sortNodeCards(filteredNodeCards);
        paginateNodeCards(filteredNodeCards, paginationContainer, 5);
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

    const savePdfBtn = document.getElementById('savePdfBtn');
    if (savePdfBtn) {
        savePdfBtn.addEventListener('click', () => {
            isPrinting = true;
            // remove all pagers
            document.querySelectorAll('.table-pagination').forEach(p => p.remove());
            // expand all <details>
            const details = document.querySelectorAll('details');
            const states = new Map();
            details.forEach(d => { states.set(d, d.open); d.open = true; });
            // fix table styles
            document.querySelectorAll('.table-container').forEach((c, i) => {
                c.style.overflow = 'visible'; c.style.height = 'auto';
            });
            document.querySelectorAll('table').forEach(t => {
                t.style.width = '100%'; t.style.tableLayout = 'fixed';
            });
            // show all rows
            document.querySelectorAll('.collapsible-container table').forEach(t => {
                Array.from(t.querySelectorAll('tr')).forEach(r => r.style.display = '');
            });
            // ensure all tabs visible
            const tabs = document.querySelectorAll('.tab-content');
            tabs.forEach(tc => tc.classList.add('active'));

            setTimeout(() => window.print(), 500);

            window.onafterprint = () => {
                isPrinting = false;
                // restore <details>
                details.forEach(d => d.open = states.get(d));
                // restore table styles
                document.querySelectorAll('.table-container').forEach((c, i) => {
                    c.style.overflow = ''; c.style.height = '';
                });
                document.querySelectorAll('table').forEach(t => {
                    t.style.tableLayout = '';
                });
                // re-paginate open details
                document.querySelectorAll('.collapsible-container').forEach(c => {
                    if (c.querySelector('details').open) paginateTable(c);
                });
            };
        });

        window.addEventListener('afterprint', () => {
            if (isPrinting) {
                isPrinting = false;
                document.querySelectorAll('.collapsible-container').forEach(c => {
                    if (c.querySelector('details').open) paginateTable(c);
                });
            }
        });
    }

    // COLLAPSIBLE + PAGINATION + SORTING SETUP (your unified block)
    document.querySelectorAll('.collapsible-container > details').forEach(detail => {
        const container = detail.parentElement;
        const summary = detail.querySelector('summary');
        const origText = summary.textContent;
        detail.addEventListener('toggle', () => {
            if (!summary.dataset.originalText) summary.dataset.originalText = origText;
            summary.textContent = detail.open
                ? summary.dataset.originalText.replace(/^Show/i, 'Hide')
                : summary.dataset.originalText.replace(/^Hide/i, 'Show');
            if (detail.open) setTimeout(() => paginateTable(container), 200);
            else {
                const pager = container.querySelector('.table-pagination');
                if (pager) pager.remove();
            }
        });
        // wire up <th> clicks
        const tbl = container.querySelector('table');
        if (tbl) {
            tbl.querySelectorAll('th').forEach((th, i) => {
                th.style.cursor = 'pointer';
                th.addEventListener('click', () => {
                    sortTable(container, i);
                    paginateTable(container);
                });
            });
        }
        if (detail.open) setTimeout(() => paginateTable(container), 200);
    });

    // Tab-switching UI (ripple + activate + re-paginate)
    const tabsEls = document.querySelectorAll('.tabs li[data-tab]');
    const contents = document.querySelectorAll('.tab-content');

    tabsEls.forEach(tab => {
        tab.addEventListener('click', e => {
            // 1) ripple
            const ripple = document.createElement('span');
            ripple.className = 'ripple';
            ripple.style.left = `${e.offsetX}px`;
            ripple.style.top = `${e.offsetY}px`;
            tab.appendChild(ripple);
            setTimeout(() => ripple.remove(), 600);

            // 2) activate tab + panel
            tabsEls.forEach(t => t.classList.remove('active'));
            contents.forEach(c => c.classList.remove('active'));

            tab.classList.add('active');
            const name = tab.getAttribute('data-tab');
            const panel = document.getElementById(name);
            if (panel) {
                panel.classList.add('active');

                // 3) re-paginate any open details inside
                panel.querySelectorAll('.collapsible-container').forEach(container => {
                    const d = container.querySelector('details');
                    if (d && d.open) paginateTable(container);
                });
            }
        });
    });

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
        let current = 1;
        const cards = Array.from(container.children);
        const totalPages = () => Math.ceil(cards.length / pageSize);
        function show() {
            const start = (current - 1) * pageSize;
            cards.forEach((c, i) => c.style.display = (i >= start && i < start + pageSize) ? '' : 'none');
        }
        function update() {
            pagination.innerHTML = '';
            // prev
            const prev = document.createElement('button');
            prev.textContent = '←'; prev.disabled = current === 1;
            prev.onclick = () => { current--; update(); };
            pagination.append(prev);
            // pages
            for (let i = 1; i <= totalPages(); i++) {
                const btn = document.createElement('button');
                btn.textContent = i;
                if (i === current) btn.classList.add('active');
                btn.onclick = () => { current = i; update(); };
                pagination.append(btn);
            }
            // next
            const next = document.createElement('button');
            next.textContent = '→'; next.disabled = current === totalPages();
            next.onclick = () => { current++; update(); };
            pagination.append(next);
        }
        show(); update();
    }


    // Updated paginateTable signature & body:
    function paginateTable(details) {
        const table = details.querySelector('table');
        if (!table) return;

        // nuke old pager
        const old = details.querySelector('.table-pagination');
        if (old) old.remove();

        // grab *all* rows, split off the first
        const allRows = Array.from(table.querySelectorAll('tr'));
        if (allRows.length === 0) return;
        const headerRow = allRows.shift();   // preserve this
        const dataRows = allRows;           // these get paginated

        let currentPage = 1;
        let pageSize = 5;

        // make a pager container inside <details>
        const pager = document.createElement('div');
        pager.className = 'table-pagination';
        details.appendChild(pager);

        const totalPages = () => Math.ceil(dataRows.length / pageSize);

        function showPage() {
            // hide *all* data-rows, then show just the slice
            dataRows.forEach(r => r.style.display = 'none');
            const start = (currentPage - 1) * pageSize;
            dataRows.slice(start, start + pageSize)
                .forEach(r => r.style.display = '');
        }

        function updateControls() {
            pager.innerHTML = '';

            // ←
            const prev = document.createElement('button');
            prev.textContent = '←';
            prev.disabled = currentPage === 1;
            prev.addEventListener('click', () => { currentPage--; update(); });
            pager.appendChild(prev);

            // pages
            for (let i = 1; i <= totalPages(); i++) {
                const btn = document.createElement('button');
                btn.textContent = i;
                if (i === currentPage) btn.classList.add('active');
                btn.addEventListener('click', () => { currentPage = i; update(); });
                pager.appendChild(btn);
            }

            // →
            const next = document.createElement('button');
            next.textContent = '→';
            next.disabled = currentPage === totalPages();
            next.addEventListener('click', () => { currentPage++; update(); });
            pager.appendChild(next);

            // size selector
            const sel = document.createElement('select');
            [5, 10, 25, 50].forEach(n => {
                const opt = document.createElement('option');
                opt.value = n; opt.textContent = `${n} per page`;
                if (n === pageSize) opt.selected = true;
                sel.appendChild(opt);
            });
            sel.addEventListener('change', () => {
                pageSize = +sel.value;
                currentPage = 1;
                update();
            });
            pager.appendChild(sel);
        }

        function update() {
            showPage();
            updateControls();
        }

        // start!
        update();
    }

});

function switchTab(tabName) {
    document.querySelectorAll('.tab-content').forEach(tc => tc.classList.remove('active'));
    document.querySelectorAll('.tabs li').forEach(t => t.classList.remove('active'));
    document.getElementById(tabName)?.classList.add('active');
    document.querySelector(`.tabs li[data-tab="${tabName}"]`)?.classList.add('active');
}

// sortNodeCards helper (for filteredNodeCards)
function sortNodeCards(container) {
    const cards = Array.from(container.querySelectorAll('.collapsible-container'));
    const rank = c => {
        const cls = Array.from(c.querySelectorAll('.metric-badge')).map(b => b.className);
        if (cls.some(x => x.includes('critical'))) return 0;
        if (cls.some(x => x.includes('warning'))) return 1;
        return 2;
    };
    cards.sort((a, b) => {
        const r = rank(a) - rank(b);
        if (r !== 0) return r;
        return a.querySelector('.node-name').textContent
            .localeCompare(b.querySelector('.node-name').textContent);
    });
    cards.forEach(c => container.appendChild(c));
}