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

    function getScoreColor(score) {
        if (score < 50) return '#B71C1C';
        if (score < 80) return '#ffa000';
        return '#4CAF50';
    }

    const filteredNodeCards = document.getElementById('filteredNodeCards');
    const paginationContainer = document.getElementById('nodeCardPagination');
    const nodeFilterInput = document.getElementById('nodeFilterInput');

    if (filteredNodeCards && paginationContainer) {
        sortNodeCards(filteredNodeCards);
        paginateNodeCards(filteredNodeCards, paginationContainer, 5);
    }

    let recBoxes = document.querySelectorAll('.recommendation-box');

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
            if (isZoomed) return;
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
            progress.style.setProperty('--stripe-base', color);
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

    let detailsState = new Map();
    let activeTabName = null;

    const nodeCards = document.getElementById('filteredNodeCards');
    const nodeCardsPager = document.getElementById('nodeCardPagination');

    function beforePrint() {
        // ── CAPTURE STATE ───────────────────────────────
        detailsState.clear();
        document.querySelectorAll('details').forEach(d => {
            detailsState.set(d, d.open);
            d.open = true;
        });
        const activeLi = document.querySelector('.tabs li.active');
        activeTabName = activeLi?.dataset.tab || null;

        // ── FLATTEN FOR PRINT ────────────────────────────
        document.querySelectorAll('.table-pagination').forEach(p => p.remove());
        document.querySelectorAll('.table-container').forEach(c => {
            c.style.overflow = 'visible';
            c.style.height = 'auto';
        });
        document.querySelectorAll('table').forEach(t => {
            t.style.width = '100%';
            t.style.tableLayout = 'fixed';
        });
        document
            .querySelectorAll('.collapsible-container table tr')
            .forEach(r => r.style.display = '');
        document.querySelectorAll('.tab-content').forEach(tc => tc.classList.add('active'));
        recBoxes.forEach(el => {
            el.style.overflow = 'visible';
            el.style.height = 'auto';
        });

        if (filteredNodeCards && paginationContainer) {
            filteredNodeCards.querySelectorAll('.collapsible-container')
                .forEach(card => card.style.display = '');
            paginationContainer.style.display = 'none';
        }

        // ── expand all node cards ─────────────────────────
        if (nodeCardsContainer && nodeCardsPager) {
            // show every single card
            Array.from(nodeCardsContainer.children)
                .forEach(card => card.style.display = '');
            // hide the pager
            nodeCardsPager.style.display = 'none';
        }
    }

    function afterPrint() {
        // ── restore node cards pagination ─────────────────
        if (nodeCards && nodeCardsPager) {
            nodeCardsPager.style.display = '';
            paginateNodeCards(nodeCards, nodeCardsPager, 5);
        }
        // ── RESTORE STATE ────────────────────────────────
        detailsState.forEach((wasOpen, d) => d.open = wasOpen);

        document.querySelectorAll('.tab-content').forEach(tc => tc.classList.remove('active'));
        document.querySelectorAll('.tabs li').forEach(li => li.classList.remove('active'));
        if (activeTabName) {
            document.querySelector(`.tabs li[data-tab="${activeTabName}"]`)?.classList.add('active');
            document.getElementById(activeTabName)?.classList.add('active');
        }

        document.querySelectorAll('.table-container').forEach(c => {
            c.style.overflow = '';
            c.style.height = '';
        });
        document.querySelectorAll('table').forEach(t => {
            t.style.tableLayout = '';
        });

        document.querySelectorAll('.collapsible-container').forEach(c => {
            const d = c.querySelector('details');
            if (d.open) paginateTable(c);
        });
        recBoxes.forEach(el => {
            el.style.overflow = '';
            el.style.height = '';
        });

        if (filteredNodeCards && paginationContainer) {
            paginationContainer.style.display = '';
            paginateNodeCards(filteredNodeCards, paginationContainer, 5);
        }
    }

    window.addEventListener('beforeprint', beforePrint);
    window.addEventListener('afterprint', afterPrint);

    document.getElementById('savePdfBtn')?.addEventListener('click', () => window.print());

    // COLLAPSIBLE + PAGINATION + SORTING SETUP
    document.querySelectorAll('.collapsible-container > details').forEach(detail => {
        const container = detail.parentElement;
        const summary = detail.querySelector('summary');
        // stash the full HTML (with your badges) so we can swap only the word
        const origHTML = summary.innerHTML;

        detail.addEventListener('toggle', () => {
            // swap just the leading word "Show"/"Hide" in that HTML
            summary.innerHTML = detail.open
                ? origHTML.replace(/^Show\b/i, 'Hide')
                : origHTML.replace(/^Hide\b/i, 'Show');

            // pagination: add when open, remove when closed
            if (detail.open) {
                setTimeout(() => paginateTable(container), 200);
            } else {
                const pager = container.querySelector('.table-pagination');
                if (pager) pager.remove();
            }
        });

        // if the node starts open, paginate right away
        if (detail.open) {
            setTimeout(() => paginateTable(container), 200);
        }

        // wire up each <th> to sort & re-paginate
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

    function initPodSizingProfileSelector() {
        let details = document.querySelector('details#PROM007');
        if (!details) {
            const fallback = document.getElementById('PROM007');
            if (fallback && fallback.tagName && fallback.tagName.toLowerCase() === 'details') {
                details = fallback;
            }
        }
        if (!details) return;
        const table = details.querySelector('table');
        if (!table) return;

        const rows = Array.from(table.querySelectorAll('tr')).slice(1);
        if (!rows.length) return;
        const headerCells = Array.from(table.querySelectorAll('tr:first-child th'));
        const profileColIndex = headerCells.findIndex(th => th.textContent.trim().toLowerCase() === 'sizing profile');

        rows.forEach(r => {
            const explicitProfile = (r.getAttribute('data-sizing-profile') || '').trim().toLowerCase();
            if (explicitProfile) {
                r.dataset.sizingProfile = explicitProfile;
            } else if (profileColIndex >= 0) {
                r.dataset.sizingProfile = (r.cells[profileColIndex]?.textContent || '').trim().toLowerCase();
            }
        });

        const profiles = Array.from(new Set(
            rows.map(r => (r.dataset.sizingProfile || '').trim().toLowerCase()).filter(Boolean)
        ));

        const namespaceColIndex = headerCells.findIndex(th => th.textContent.trim().toLowerCase() === 'namespace');
        rows.forEach(r => {
            if (namespaceColIndex >= 0) {
                r.dataset.namespaceValue = (r.cells[namespaceColIndex]?.textContent || '').trim().toLowerCase();
            } else {
                r.dataset.namespaceValue = '';
            }
        });
        const namespaces = Array.from(new Set(
            rows.map(r => (r.dataset.namespaceValue || '').trim().toLowerCase()).filter(Boolean)
        ));

        rows.forEach(r => {
            const p = (r.dataset.sizingProfile || '').trim().toLowerCase();
            r.dataset.sizingProfile = p;
            r.dataset.profileHidden = 'false';
            r.dataset.namespaceHidden = 'false';
        });

        const controls = document.createElement('div');
        controls.className = 'profile-filter';
        controls.style.margin = '0 0 10px 0';

        const escapeCsv = (value) => {
            const str = (value ?? '').toString().replace(/\r?\n|\r/g, ' ').trim();
            return `"${str.replace(/"/g, '""')}"`;
        };

        const exportProm007Csv = () => {
            const headerCellsAll = Array.from(table.querySelectorAll('tr:first-child th'));
            if (!headerCellsAll.length) return;

            const visibleColIndexes = [];
            const headerTitles = [];
            const profileHeaderIndex = headerCellsAll.findIndex(th =>
                (th.textContent || '').trim().toLowerCase() === 'sizing profile'
            );
            headerCellsAll.forEach((th, idx) => {
                if (window.getComputedStyle(th).display === 'none') return;
                visibleColIndexes.push(idx);
                headerTitles.push(th.textContent.trim());
            });
            if (profileHeaderIndex >= 0 && !visibleColIndexes.includes(profileHeaderIndex)) {
                visibleColIndexes.push(profileHeaderIndex);
                headerTitles.push('Sizing Profile');
            }

            const exportRows = rows.filter(r =>
                r.dataset.profileHidden !== 'true' &&
                r.dataset.namespaceHidden !== 'true'
            );

            const lines = [];
            lines.push(headerTitles.map(escapeCsv).join(','));
            exportRows.forEach(r => {
                const vals = visibleColIndexes.map(i => {
                    if (profileHeaderIndex >= 0 && i === profileHeaderIndex) {
                        const explicitProfile = (r.dataset.sizingProfile || '').trim();
                        if (explicitProfile) {
                            return escapeCsv(explicitProfile.charAt(0).toUpperCase() + explicitProfile.slice(1));
                        }
                    }
                    const cell = r.cells[i];
                    return escapeCsv(cell ? cell.textContent.trim() : '');
                });
                lines.push(vals.join(','));
            });

            const csvContent = lines.join('\r\n');
            const bom = '\uFEFF';
            const blob = new Blob([bom + csvContent], { type: 'text/csv;charset=utf-8;' });
            const url = URL.createObjectURL(blob);

            const ts = new Date();
            const pad = (n) => `${n}`.padStart(2, '0');
            const stamp = `${ts.getFullYear()}${pad(ts.getMonth() + 1)}${pad(ts.getDate())}-${pad(ts.getHours())}${pad(ts.getMinutes())}${pad(ts.getSeconds())}`;
            const reportTitle = Array.from(document.querySelectorAll('.header .header-top span'))
                .map(s => (s.textContent || '').trim())
                .find(t => t.toLowerCase().startsWith('kubernetes cluster report:')) || '';
            const rawClusterName = reportTitle.split(':').slice(1).join(':').trim() || 'cluster';
            const clusterSlug = rawClusterName
                .toLowerCase()
                .replace(/[^a-z0-9._-]+/g, '-')
                .replace(/-+/g, '-')
                .replace(/^-|-$/g, '') || 'cluster';
            const filename = `${clusterSlug}-pod-sizing-${stamp}.csv`;

            const a = document.createElement('a');
            a.href = url;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        };

        const profileLabel = document.createElement('span');
        profileLabel.className = 'filter-label';
        profileLabel.textContent = 'Profile: ';
        profileLabel.style.marginRight = '8px';

        const profileSelect = document.createElement('select');
        profileSelect.className = 'filter-select';
        const profileOptions = (profiles.length > 1) ? ['all', ...profiles] : profiles;
        profileOptions.forEach(p => {
            const opt = document.createElement('option');
            opt.value = p;
            opt.textContent = p === 'all' ? 'All Profiles' : (p.charAt(0).toUpperCase() + p.slice(1));
            profileSelect.appendChild(opt);
        });

        if (profiles.length > 1) {
            if (profiles.includes('balanced')) {
                profileSelect.value = 'balanced';
            } else {
                profileSelect.value = 'all';
            }
        } else {
            profileSelect.value = profiles[0] || '';
            profileSelect.disabled = true;
        }

        const namespaceLabel = document.createElement('span');
        namespaceLabel.className = 'filter-label';
        namespaceLabel.textContent = 'Namespace: ';
        namespaceLabel.style.marginRight = '8px';

        const namespaceSelect = document.createElement('select');
        namespaceSelect.className = 'filter-select';
        ['all', ...namespaces].forEach(ns => {
            const opt = document.createElement('option');
            opt.value = ns;
            opt.textContent = ns === 'all' ? 'All Namespaces' : ns;
            namespaceSelect.appendChild(opt);
        });
        namespaceSelect.value = 'all';

        const applyFilter = () => {
            const selectedProfile = profileSelect.value;
            const selectedNamespace = namespaceSelect.value;
            rows.forEach(r => {
                const rowProfile = r.dataset.sizingProfile || '';
                const rowNamespace = r.dataset.namespaceValue || '';
                r.dataset.profileHidden = (selectedProfile !== 'all' && selectedProfile && rowProfile !== selectedProfile) ? 'true' : 'false';
                r.dataset.namespaceHidden = (selectedNamespace !== 'all' && rowNamespace !== selectedNamespace) ? 'true' : 'false';
            });
            if (details.open) {
                paginateTable(details);
            } else {
                const pager = details.querySelector('.table-pagination');
                if (pager) pager.remove();
            }
        };

        profileSelect.addEventListener('change', applyFilter);
        namespaceSelect.addEventListener('change', applyFilter);

        const exportBtn = document.createElement('button');
        exportBtn.type = 'button';
        exportBtn.className = 'filter-button';
        exportBtn.textContent = 'Export CSV';
        exportBtn.addEventListener('click', exportProm007Csv);

        controls.appendChild(profileLabel);
        controls.appendChild(profileSelect);
        controls.appendChild(namespaceLabel);
        controls.appendChild(namespaceSelect);
        controls.appendChild(exportBtn);
        table.insertAdjacentElement('beforebegin', controls);
        applyFilter();
    }

    initPodSizingProfileSelector();

    function buildCompactPageList(total, current, edgeCount = 1, aroundCount = 1) {
        const pages = new Set();
        for (let i = 1; i <= Math.min(edgeCount, total); i++) pages.add(i);
        for (let i = Math.max(1, total - edgeCount + 1); i <= total; i++) pages.add(i);
        for (let i = Math.max(1, current - aroundCount); i <= Math.min(total, current + aroundCount); i++) pages.add(i);

        const sorted = Array.from(pages).sort((a, b) => a - b);
        const sequence = [];
        let prev = null;
        for (const p of sorted) {
            if (prev !== null && p - prev > 1) sequence.push('...');
            sequence.push(p);
            prev = p;
        }
        return sequence;
    }


    function paginateNodeCards(container, pagination, initialPageSize) {
        if (!container || !pagination) return;

        let currentPage = 1;
        let pageSize = initialPageSize;  // now mutable

        function getCards() {
            return Array.from(container.children);
        }

        function totalPages(cards) {
            return Math.ceil(cards.length / pageSize) || 1;
        }

        function render(cards) {
            const start = (currentPage - 1) * pageSize;
            const end = start + pageSize;
            cards.forEach((card, idx) => {
                card.style.display = (idx >= start && idx < end) ? '' : 'none';
            });
        }

        function updateControls(cards) {
            pagination.innerHTML = '';

            // Prev button
            const prev = document.createElement('button');
            prev.textContent = '←';
            prev.disabled = currentPage === 1;
            prev.addEventListener('click', () => {
                currentPage = Math.max(1, currentPage - 1);
                update();
            });
            pagination.appendChild(prev);

            const pages = totalPages(cards);
            const pageSequence = buildCompactPageList(pages, currentPage, 1, 1);
            pageSequence.forEach(token => {
                if (token === '...') {
                    const ellipsis = document.createElement('span');
                    ellipsis.className = 'pager-ellipsis';
                    ellipsis.textContent = '...';
                    pagination.appendChild(ellipsis);
                    return;
                }
                const btn = document.createElement('button');
                btn.textContent = token;
                if (token === currentPage) btn.classList.add('active');
                btn.addEventListener('click', () => {
                    currentPage = token;
                    update();
                });
                pagination.appendChild(btn);
            });

            // Next button
            const next = document.createElement('button');
            next.textContent = '→';
            next.disabled = currentPage === pages;
            next.addEventListener('click', () => {
                currentPage = Math.min(pages, currentPage + 1);
                update();
            });
            pagination.appendChild(next);

            // **Cards-per-page selector**
            const sel = document.createElement('select');
            [5, 10, 25, 50].forEach(n => {
                const opt = document.createElement('option');
                opt.value = n;
                opt.textContent = `${n} per page`;
                if (n === pageSize) opt.selected = true;
                sel.appendChild(opt);
            });
            sel.addEventListener('change', () => {
                pageSize = +sel.value;
                currentPage = 1;
                update();
            });
            pagination.appendChild(sel);
        }

        function update() {
            const cards = getCards();
            const pages = totalPages(cards);
            if (currentPage > pages) currentPage = pages;

            render(cards);
            updateControls(cards);
        }

        // initial render
        update();
    }

    // Updated paginateTable signature & body:
    function paginateTable(target) {
        const details = target && target.tagName && target.tagName.toLowerCase() === 'details'
            ? target
            : target?.querySelector?.('details');
        if (!details) return;

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

        const visibleRows = () => dataRows.filter(r =>
            r.dataset.profileHidden !== 'true' &&
            r.dataset.namespaceHidden !== 'true'
        );
        const totalPages = () => Math.max(1, Math.ceil(visibleRows().length / pageSize));

        function showPage() {
            // hide *all* data-rows, then show just the slice
            dataRows.forEach(r => r.style.display = 'none');
            const candidateRows = visibleRows();
            const start = (currentPage - 1) * pageSize;
            candidateRows.slice(start, start + pageSize)
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

            const pages = totalPages();
            const pageSequence = buildCompactPageList(pages, currentPage, 1, 1);
            pageSequence.forEach(token => {
                if (token === '...') {
                    const ellipsis = document.createElement('span');
                    ellipsis.className = 'pager-ellipsis';
                    ellipsis.textContent = '...';
                    pager.appendChild(ellipsis);
                    return;
                }
                const btn = document.createElement('button');
                btn.textContent = token;
                if (token === currentPage) btn.classList.add('active');
                btn.addEventListener('click', () => { currentPage = token; update(); });
                pager.appendChild(btn);
            });

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

    // ──────────────────────────────────────────────────────────
    window.toggleExpand = function (panelId) {
        // find the panel
        const panel = document.getElementById(panelId);
        if (!panel) return;

        // find *this* card
        const card = panel.closest('.metric-card');
        if (!card) return;

        // toggle this panel only
        panel.classList.toggle('show');
        card.classList.toggle('expanded');
    };

    // ──────────────────────────────────────────────────────────

    // ──────────────────────────────────────────────────────────
    // let links like <a href="#MyCheckId"> … </a> open the right tab & expand the detail

    function openFromHash() {
        const hash = window.location.hash.slice(1);
        if (!hash) return;
        const detail = document.getElementById(hash);
        if (!detail) return;

        // 1) switch to its tab
        const panel = detail.closest('.tab-content');
        if (panel?.id) switchTab(panel.id);

        // 2) open *all* ancestor <details> first (so nested ones are actually visible)
        let parent = detail.parentElement;
        while (parent) {
            if (parent.tagName?.toLowerCase() === 'details' && !parent.open) {
                parent.open = true;
            }
            parent = parent.parentElement;
        }

        // 3) open the target detail
        if (!detail.open) detail.open = true;

        // 4) open any further nested <details> inside it
        detail.querySelectorAll('details').forEach(d => {
            if (!d.open) d.open = true;
        });

        // 5) scroll into view
        detail.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }

    // wire up hash-change to open+expand on direct links
    window.addEventListener('hashchange', openFromHash);
    openFromHash();

    // ── Auto-open <details> when clicking a fix link ─────────────────────────
    document.querySelectorAll('.quick-fix-card .fix-id, .check-id').forEach(link => {
      link.addEventListener('click', e => {
        const checkId = link.getAttribute('href').substring(1);
        const detailsEl = document.querySelector(`details#${checkId}`);
        if (detailsEl && detailsEl.tagName.toLowerCase() === 'details') {
          detailsEl.open = true;
          setTimeout(() => {
            detailsEl.scrollIntoView({ behavior: 'smooth', block: 'start' });
          }, 100);
        }
      });
    });
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
