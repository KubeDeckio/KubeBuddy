// Back to Top
window.addEventListener('scroll', function () {
    const button = document.getElementById('backToTop');
    if (button) button.style.display = window.scrollY > 200 ? 'block' : 'none';
});

// Global print state
let isPrinting = false;

// Utility to get color based on score
function getScoreColor(score) {
    if (score < 40) return '#B71C1C'; // Red
    if (score < 70) return '#ffa000'; // Orange
    return '#4CAF50'; // Green
}

// Consolidate all DOMContentLoaded listeners
document.addEventListener('DOMContentLoaded', () => {
    console.log('DOM fully loaded, initializing scripts');

    // Navigation Drawer
    try {
        const navDrawer = document.getElementById('navDrawer');
        const navToggle = document.getElementById('menuFab');
        const navClose = document.getElementById('navClose');
        const navScrim = document.getElementById('navScrim');

        if (!navDrawer || !navToggle || !navClose || !navScrim) {
            console.error('Navigation drawer elements missing');
            return;
        }

        function toggleDrawer() {
            const isOpen = navDrawer.classList.contains('open');
            navDrawer.classList.toggle('open');
            navScrim.classList.toggle('open');
            if (window.innerWidth <= 800) document.body.style.overflow = isOpen ? '' : 'hidden';
        }

        navToggle.addEventListener('click', toggleDrawer);
        navClose.addEventListener('click', toggleDrawer);
        navScrim.addEventListener('click', toggleDrawer);

        document.querySelectorAll('.nav-item a, .nav-item details summary').forEach(item => {
            item.addEventListener('click', function (e) {
                const rect = this.getBoundingClientRect();
                const x = e.clientX - rect.left;
                const y = e.clientY - rect.top;
                const ripple = document.createElement('span');
                ripple.classList.add('ripple');
                ripple.style.left = x + 'px';
                ripple.style.top = y + 'px';
                this.appendChild(ripple);
                setTimeout(() => ripple.remove(), 600);
            });
        });

        let lastScrollY = window.scrollY;
        window.addEventListener('scroll', function () {
            if (Math.abs(window.scrollY - lastScrollY) > 50 && navDrawer.classList.contains('open')) {
                toggleDrawer();
            }
            lastScrollY = window.scrollY;
        });
    } catch (e) {
        console.error('Navigation Drawer Error:', e);
    }

    // Save as PDF with html2canvas and jsPDF
    try {
        const savePdfBtn = document.getElementById('savePdfBtn');
        if (!savePdfBtn) {
            console.error('Save PDF button not found');
        } else {
            savePdfBtn.addEventListener('click', function () {
                isPrinting = true;
                console.log('Preparing for PDF: expanding details and removing pagination');

                // Remove pagination
                document.querySelectorAll('.table-pagination').forEach(pagination => {
                    console.log(`Pre-print: Removing pagination from ${pagination.parentElement.id}`);
                    pagination.remove();
                });

                // Expand all details
                const detailsElements = document.querySelectorAll('details');
                const detailsStates = new Map();
                detailsElements.forEach(detail => {
                    detailsStates.set(detail, detail.open);
                    detail.open = true;
                });

                // Adjust table containers for full visibility
                const tableContainers = document.querySelectorAll('.table-container');
                const tables = document.querySelectorAll('table');
                const originalStyles = [];
                tableContainers.forEach((container, index) => {
                    originalStyles[index] = { overflow: container.style.overflow, height: container.style.height };
                    container.style.overflow = 'visible';
                    container.style.height = 'auto';
                });
                tables.forEach(table => {
                    table.style.width = '100%';
                    table.style.tableLayout = 'fixed';
                });

                // Show all rows in collapsible containers
                document.querySelectorAll('.collapsible-container').forEach(container => {
                    const table = container.querySelector('table');
                    if (table) {
                        const allRows = Array.from(table.querySelectorAll('tr')).filter(row => row.cells.length > 0);
                        console.log(`Pre-print: Showing all ${allRows.length - 1} rows for ${container.id}`);
                        allRows.forEach(row => row.style.display = '');
                    }
                });

                // Show all tabs for PDF capture
                let tabContents = [], originalActiveTab = null, originalActiveContent = null;
                try {
                    tabContents = document.querySelectorAll('.tab-content');
                    originalActiveTab = document.querySelector('.tabs li.active');
                    originalActiveContent = document.querySelector('.tab-content.active');
                    tabContents.forEach(tc => tc.classList.add('active'));
                } catch (e) {
                    console.warn('Tab printing adjustment failed:', e);
                }

                // Generate PDF
                setTimeout(() => {
                    html2canvas(document.body, { scale: 2 }).then(canvas => {
                        const imgData = canvas.toDataURL('image/png');
                        const { jsPDF } = window.jspdf;
                        const pdf = new jsPDF('p', 'mm', 'a4');
                        const imgProps = pdf.getImageProperties(imgData);
                        const pdfWidth = pdf.internal.pageSize.getWidth();
                        const pdfHeight = (imgProps.height * pdfWidth) / imgProps.width;
                        pdf.addImage(imgData, 'PNG', 0, 0, pdfWidth, pdfHeight);
                        pdf.save('kubebuddy_report.pdf');

                        // Restore state
                        console.log('PDF generated, restoring original state');
                        isPrinting = false;
                        tabContents.forEach(tc => {
                            if (tc !== originalActiveContent) {
                                tc.classList.remove('active');
                            }
                        });
                        document.querySelectorAll('.tabs li').forEach(tab => tab.classList.remove('active'));
                        if (originalActiveTab) originalActiveTab.classList.add('active');

                        detailsElements.forEach(detail => detail.open = detailsStates.get(detail));
                        tableContainers.forEach((container, index) => {
                            container.style.overflow = originalStyles[index].overflow;
                            container.style.height = originalStyles[index].height;
                        });
                        tables.forEach(table => table.style.tableLayout = '');

                        document.querySelectorAll('.collapsible-container').forEach(container => {
                            if (container.querySelector('details').open) {
                                paginateTable(container);
                            }
                        });
                    }).catch(e => {
                        console.error('PDF generation failed:', e);
                    });
                }, 500);
            });
        }
    } catch (e) {
        console.error('PDF Error:', e);
    }

    // Chart.js for Cluster Charts and Node Sparklines
    try {
        // Helper function to render line charts
        function renderLineChart(canvas, label, unit) {
            if (!canvas || !canvas.dataset.values) {
                console.error(`Canvas for ${label} not found or missing data-values`);
                return;
            }
            try {
                const data = JSON.parse(canvas.dataset.values || '[]');
                if (!data.length) {
                    console.warn(`No data for ${label} chart`);
                    canvas.insertAdjacentHTML('afterend', `<p class="warning">⚠️ No data for ${label}</p>`);
                    return;
                }
                const chart = new Chart(canvas, {
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
                console.log(`Rendered ${label} chart`);
                return chart;
            } catch (e) {
                console.error(`Failed to render ${label} chart:`, e);
                canvas.insertAdjacentHTML('afterend', `<p class="warning">⚠️ Failed to render ${label}</p>`);
                return null;
            }
        }

        // Create a single lightbox overlay
        let lightbox = document.querySelector('.chart-lightbox');
        if (!lightbox) {
            lightbox = document.createElement('div');
            lightbox.className = 'chart-lightbox';
            document.body.appendChild(lightbox);
        }

        // Store chart instances for resizing
        const chartInstances = new Map();

        // Function to handle chart zoom
        function setupChartZoom(chartItem, canvas, chart, unit) {
            if (!chartItem || !canvas) {
                console.error('Chart item or canvas not found for zoom setup');
                return;
            }

            // Store original parent and next sibling for precise restoration
            const originalParent = chartItem.parentElement;
            const nextSibling = chartItem.nextSibling;

            // Add ARIA attributes
            chartItem.setAttribute('aria-label', 'Click or press Enter to enlarge chart');
            chartItem.setAttribute('aria-expanded', 'false');

            // Add zoom icon using Material Icons
            chartItem.insertAdjacentHTML('afterbegin', '<span class="chart-zoom-icon material-icons" aria-label="Click to enlarge chart">zoom_in</span>');

            // State to track zoom
            let isZoomed = false;

            // Function to enter zoom
            function enterZoom() {
                if (isPrinting || isZoomed) return;
                isZoomed = true;
                chartItem.classList.add('zoomed', 'persistent-zoom');
                chartItem.setAttribute('aria-expanded', 'true');
                lightbox.classList.add('active');
                lightbox.appendChild(chartItem);
                if (chart) {
                    chart.resize();
                }
                console.log(`Zoomed chart: ${chartItem.querySelector('h3').textContent}`);
            }

            // Function to exit zoom
            function exitZoom() {
                if (!isZoomed) return;
                isZoomed = false;
                chartItem.classList.remove('zoomed', 'persistent-zoom');
                chartItem.setAttribute('aria-expanded', 'false');
                lightbox.classList.remove('active');

                // Restore chart to original position
                try {
                    if (originalParent && originalParent.isConnected) {
                        if (nextSibling && nextSibling.isConnected) {
                            originalParent.insertBefore(chartItem, nextSibling);
                        } else {
                            originalParent.appendChild(chartItem);
                        }
                        console.log(`Restored chart to original parent: ${chartItem.querySelector('h3').textContent}`);
                    } else {
                        // Fallback: append to #summary .chart-wrapper
                        const fallbackContainer = document.querySelector('#summary .chart-wrapper');
                        if (fallbackContainer) {
                            fallbackContainer.appendChild(chartItem);
                            console.warn(`Original parent not found, restored chart to fallback container: ${chartItem.querySelector('h3').textContent}`);
                        } else {
                            console.error(`Failed to restore chart: no valid parent found for ${chartItem.querySelector('h3').textContent}`);
                        }
                    }
                } catch (e) {
                    console.error(`Error restoring chart: ${e.message}`);
                }

                if (chart) {
                    chart.resize();
                }
            }

            // Click to toggle zoom
            chartItem.addEventListener('click', (e) => {
                e.preventDefault();
                if (isZoomed) {
                    exitZoom();
                } else {
                    enterZoom();
                }
            });

            // Click lightbox to exit
            lightbox.addEventListener('click', (e) => {
                if (e.target === lightbox && isZoomed) {
                    exitZoom();
                }
            });

            // Keyboard interaction
            chartItem.setAttribute('tabindex', '0');
            chartItem.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    chartItem.click();
                }
            });
        }

        // Cluster CPU Chart
        const cpuCanvas = document.getElementById('clusterCpuChart');
        const cpuChartItem = cpuCanvas?.closest('.chart-item');
        const cpuChart = renderLineChart(cpuCanvas, 'Cluster CPU Usage', 'CPU Usage (%)');
        if (cpuChartItem && cpuCanvas) {
            chartInstances.set(cpuCanvas, cpuChart);
            setupChartZoom(cpuChartItem, cpuCanvas, cpuChart, 'CPU Usage (%)');
            console.log('CPU Chart parent structure:', cpuChartItem.parentElement.outerHTML);
        }

        // Cluster Memory Chart
        const memCanvas = document.getElementById('clusterMemChart');
        const memChartItem = memCanvas?.closest('.chart-item');
        const memChart = renderLineChart(memCanvas, 'Cluster Memory Usage', 'Memory Usage (%)');
        if (memChartItem && memCanvas) {
            chartInstances.set(memCanvas, memChart);
            setupChartZoom(memChartItem, memCanvas, memChart, 'Memory Usage (%)');
            console.log('Memory Chart parent structure:', memChartItem.parentElement.outerHTML);
        }

        // Pod Count Chart
        const podCanvas = document.getElementById('podCountChart');
        const podChartItem = podCanvas?.closest('.chart-item');
        const podChart = renderLineChart(podCanvas, 'Total Pods', 'Pod Count');
        if (podChartItem && podCanvas) {
            chartInstances.set(podCanvas, podChart);
            setupChartZoom(podChartItem, podCanvas, podChart, 'Pod Count');
        }

        // Pod Restarts Chart
        const restartCanvas = document.getElementById('restartChart');
        const restartChartItem = restartCanvas?.closest('.chart-item');
        const restartChart = renderLineChart(restartCanvas, 'Pod Restarts', 'Restarts');
        if (restartChartItem && restartCanvas) {
            chartInstances.set(restartCanvas, restartChart);
            setupChartZoom(restartChartItem, restartCanvas, restartChart, 'Restarts');
        }

        // Node Count Gauge
        const nodeChart = document.getElementById('nodeCountChart');
        const nodeChartItem = nodeChart?.closest('.chart-item');
        if (nodeChart && nodeChart.dataset.values) {
            try {
                const data = JSON.parse(nodeChart.dataset.values || '{}');
                if (!data.value) {
                    console.warn('No data for Node Count chart');
                    nodeChart.insertAdjacentHTML('afterend', '<p class="warning">⚠️ No data for Node Count</p>');
                    return;
                }
                const chart = new Chart(nodeChart, {
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
                chartInstances.set(nodeChart, chart);
                setupChartZoom(nodeChartItem, nodeChart, chart, 'Node Count');
                console.log('Rendered Node Count chart');
            } catch (e) {
                console.error('Failed to render Node Count chart:', e);
                nodeChart.insertAdjacentHTML('afterend', '<p class="warning">⚠️ Failed to render Node Count chart</p>');
            }
        }

        // Node Sparklines (no zoom effect)
        document.querySelectorAll('.sparkline').forEach(canvas => {
            try {
                const values = JSON.parse(canvas.dataset.values || '[]');
                if (!values.length) {
                    console.warn('No data for sparkline');
                    return;
                }
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
                console.error('Failed to render sparkline:', e);
                canvas.insertAdjacentHTML('afterend', '<span class="warning">⚠️ Invalid sparkline data</span>');
            }
        });
    } catch (e) {
        console.error('Chart.js Error:', e);
    }

    // Collapsible Toggle, Pagination, and Sorting Setup
    try {
        const containers = document.querySelectorAll('.container');
        console.log(`Found ${containers.length} containers`);
        containers.forEach(container => {
            const details = container.querySelectorAll('.collapsible-container > details');
            console.log(`Found ${details.length} details in container`);
            details.forEach(detail => {
                const collapsibleContainer = detail.parentElement;
                const id = collapsibleContainer.id;
                if (!id) {
                    console.log('Skipping collapsible with no ID');
                    return;
                }
                const summary = detail.querySelector('summary');
                const defaultText = summary.textContent;

                console.log(`Setting up collapsible for ID: ${id}`);

                collapsibleContainer.sortState = {
                    columnIndex: null,
                    ascending: true
                };

                detail.addEventListener('toggle', () => {
                    if (!summary.getAttribute('data-original-text')) {
                        summary.setAttribute('data-original-text', defaultText);
                    }

                    const originalText = summary.getAttribute('data-original-text');

                    if (detail.open) {
                        summary.textContent = originalText.replace('Show', 'Hide');
                    } else {
                        summary.textContent = originalText.replace('Hide', 'Show');
                    }

                    const pagination = collapsibleContainer.querySelector('.table-pagination');

                    if (detail.open) {
                        console.log(`Toggled open: ${id}, calling paginateTable`);
                        setTimeout(() => paginateTable(collapsibleContainer), 200);
                    } else if (pagination) {
                        pagination.remove();
                        console.log(`Toggled closed: ${id}, removed pagination`);
                    }
                });

                const table = collapsibleContainer.querySelector('table');
                if (table) {
                    const headers = table.querySelectorAll('th');
                    headers.forEach((header, index) => {
                        header.style.cursor = 'pointer';
                        header.addEventListener('click', () => {
                            sortTable(collapsibleContainer, index);
                            paginateTable(collapsibleContainer);
                        });
                    });
                }

                if (detail.open) {
                    console.log(`Initial open state detected for ${id}`);
                    setTimeout(() => paginateTable(collapsibleContainer), 200);
                }
            });
        });
    } catch (e) {
        console.error('Collapsible/Pagination/Sorting Setup Error:', e);
    }

    // Tab Switching
    const tabs = document.querySelectorAll('.tabs li');
    const tabContents = document.querySelectorAll('.tab-content');

    tabs.forEach(tab => {
        tab.addEventListener('click', function (e) {
            const ripple = document.createElement('span');
            ripple.className = 'ripple';
            const rect = this.getBoundingClientRect();
            ripple.style.left = (e.clientX - rect.left) + 'px';
            ripple.style.top = (e.clientY - rect.top) + 'px';
            this.appendChild(ripple);
            setTimeout(() => ripple.remove(), 600);

            tabs.forEach(t => t.classList.remove('active'));
            tabContents.forEach(tc => tc.classList.remove('active'));
            tab.classList.add('active');

            const target = tab.getAttribute('data-tab');
            const content = document.getElementById(target);
            if (content) {
                content.classList.add('active');

                const containers = content.querySelectorAll('.collapsible-container');
                containers.forEach(container => {
                    const details = container.querySelector('details');
                    if (details && details.open) {
                        paginateTable(container);
                    }
                });
            }
        });
    });

    // Navigation Drawer Items
    const tabList = document.querySelectorAll('.header .tabs li');
    const navItemsContainer = document.querySelector('#navDrawer .nav-items');

    if (navItemsContainer) {
        navItemsContainer.innerHTML = '';

        tabList.forEach(tab => {
            const target = tab.getAttribute('data-tab') || tab.textContent.trim().toLowerCase();
            const li = document.createElement('li');
            li.className = 'nav-item';
            const a = document.createElement('a');
            a.href = '#' + target;
            a.textContent = tab.textContent.trim();
            li.appendChild(a);
            navItemsContainer.appendChild(li);
        });

        navItemsContainer.querySelectorAll('.nav-item a').forEach(link => {
            link.addEventListener('click', function (e) {
                e.preventDefault();
                const target = this.getAttribute('href').substring(1);

                const tabToActivate = document.querySelector(`.header .tabs li[data-tab="${target}"]`);
                if (tabToActivate) tabToActivate.click();

                const tabContent = document.getElementById(target);
                if (tabContent) {
                    tabContent.scrollIntoView({ behavior: 'smooth', block: 'start' });
                }

                document.getElementById('navDrawer').classList.remove('open');
                document.getElementById('navScrim').classList.remove('open');
                document.body.style.overflow = '';
            });
        });
    }

    // Tabs Overflow Check
    const tabsContainer = document.querySelector('.header .tabs');
    const menuFab = document.getElementById('menuFab');

    function checkTabsOverflow() {
        if (tabsContainer && menuFab) {
            menuFab.style.display = 'flex';
            if (tabsContainer.scrollWidth > tabsContainer.clientWidth || window.innerWidth <= 600) {
                tabsContainer.style.display = 'none';
            } else {
                tabsContainer.style.display = 'flex';
            }
        }
    }

    checkTabsOverflow();
    window.addEventListener('resize', checkTabsOverflow);

    // Cluster Health Score Progress Bar
    const progressBars = document.querySelectorAll('.progress-bar');
    progressBars.forEach(bar => {
        let score = parseFloat(bar.style.getPropertyValue('--cluster-score')) || 0;

        if (score === 0) {
            const scoreElement = bar.parentElement.querySelector('p');
            const scoreText = scoreElement?.textContent.match(/Score: (\d+)/)?.[1];
            score = parseFloat(scoreText) || 0;
        }

        const progress = bar.querySelector('.progress');
        const dot = bar.querySelector('.pulse-dot');
        const color = getScoreColor(score);

        requestAnimationFrame(() => {
            progress.style.width = `${score}%`;
            progress.style.background = color;
            setTimeout(() => {
                if (dot) {
                    dot.style.left = `${score - 4}%`;
                    dot.style.display = 'block';
                    dot.style.background = color;
                    dot.style.border = `4px solid ${color}`;
                    dot.style.opacity = '1';
                }
            }, 1000);
        });
    });

    // Status Chip Animation
    try {
        const statusContainer = document.querySelector('.status-container');
        const statusChip = document.querySelector('.status-chip');
        const countElements = document.querySelectorAll('.count-up');

        if (statusContainer && statusChip && countElements.length) {
            const percent = parseFloat(statusContainer.getAttribute('data-percent') || '0');
            const color = getScoreColor(percent);
            statusChip.style.background = color;
            console.log('Status chip colored:', color, 'percent:', percent);

            function animateCountUp(element, target, duration) {
                let start = 0;
                const increment = target / (duration / 16);
                let current = start;

                const timer = setInterval(() => {
                    current += increment;
                    if (current >= target) {
                        current = target;
                        clearInterval(timer);
                    }
                    element.textContent = Math.round(current);
                }, 16);
            }

            countElements.forEach(element => {
                const target = parseInt(element.getAttribute('data-count'), 10);
                animateCountUp(element, target, 1500);
            });
        } else {
            console.error('Status chip or count elements not found');
        }
    } catch (e) {
        console.error('Status Chip Animation Error:', e);
    }
});

// Sorting Function
function sortTable(collapsibleContainer, columnIndex) {
    try {
        const id = collapsibleContainer.id;
        console.log(`sortTable called for ID: ${id}, column: ${columnIndex}`);
        const table = collapsibleContainer.querySelector('table');
        if (!table) {
            console.error(`Table not found in collapsible container: ${id}`);
            return;
        }

        const allRows = Array.from(table.querySelectorAll('tr')).filter(row => row.cells.length > 0);
        const headerRow = allRows.find(row => row.querySelector('th')) || null;
        const dataRows = headerRow ? allRows.filter(row => row !== headerRow) : allRows;

        const sortState = collapsibleContainer.sortState;
        if (sortState.columnIndex === columnIndex) {
            sortState.ascending = !sortState.ascending;
        } else {
            sortState.columnIndex = columnIndex;
            sortState.ascending = true;
        }

        const headers = table.querySelectorAll('th');
        headers.forEach((header, idx) => {
            header.innerHTML = header.innerHTML.replace(/ <span class="sort-arrow">.*<\/span>$/, '');
            if (idx === columnIndex) {
                header.innerHTML += ` <span class="sort-arrow">${sortState.ascending ? '↑' : '↓'}</span>`;
            }
        });

        dataRows.sort((rowA, rowB) => {
            let cellA = rowA.cells[columnIndex].textContent.trim();
            let cellB = rowB.cells[columnIndex].textContent.trim();

            if (columnIndex === 4 && cellA.includes('PASS') && cellB.includes('FAIL')) {
                return sortState.ascending ? -1 : 1;
            } else if (columnIndex === 4 && cellA.includes('FAIL') && cellB.includes('PASS')) {
                return sortState.ascending ? 1 : -1;
            }

            if (columnIndex === 2) {
                const severityOrder = { 'High': 3, 'Medium': 2, 'Low': 1 };
                const valA = severityOrder[cellA] || 0;
                const valB = severityOrder[cellB] || 0;
                return sortState.ascending ? valA - valB : valB - valA;
            }

            const isNumeric = !isNaN(parseFloat(cellA)) && !isNaN(parseFloat(cellB));
            if (isNumeric) {
                return sortState.ascending ? parseFloat(cellA) - parseFloat(cellB) : parseFloat(cellB) - parseFloat(cellA);
            } else {
                return sortState.ascending ? cellA.localeCompare(cellB) : cellB.localeCompare(cellA);
            }
        });

        const fragment = document.createDocumentFragment();
        dataRows.forEach(row => fragment.appendChild(row));
        const tbody = table.querySelector('tbody') || table;
        tbody.appendChild(fragment);

        console.log(`Table sorted for ${id}, column ${columnIndex}, ascending: ${sortState.ascending}`);
    } catch (e) {
        console.error(`Sorting Error for ${collapsibleContainer.id}:`, e);
    }
}

// Pagination Function with Sliding Window
function paginateTable(collapsibleContainer) {
    try {
        const id = collapsibleContainer.id;
        console.log(`paginateTable called for ID: ${id}`);
        if (!collapsibleContainer.classList.contains('collapsible-container')) {
            console.error(`Element with ID ${id} is not a collapsible-container`);
            return;
        }

        const table = collapsibleContainer.querySelector('table');
        if (!table) {
            console.error(`Table not found in collapsible container: ${id}`);
            return;
        }

        const allRows = Array.from(table.querySelectorAll('tr')).filter(row => row.cells.length > 0);
        const headerRow = allRows.find(row => row.querySelector('th')) || null;
        const dataRows = headerRow ? allRows.filter(row => row !== headerRow) : allRows;

        console.log(`Found ${headerRow ? 1 : 0} header row and ${dataRows.length} data rows in table for ${id}`);

        if (isPrinting) {
            console.log(`Printing mode: showing all ${dataRows.length} rows for ${id} (pagination skipped)`);
            allRows.forEach(row => row.style.display = '');
            return;
        }

        if (dataRows.length < 10) {
            console.log(`Fewer than 10 data rows for ${id}, skipping pagination`);
            allRows.forEach(row => row.style.display = '');
            const existingPagination = collapsibleContainer.querySelector('.table-pagination');
            if (existingPagination) existingPagination.remove();
            return;
        }

        let currentPage = 1;
        let pageSize = 10;
        let totalPages = Math.ceil(dataRows.length / pageSize);
        const maxVisiblePages = 5;

        let pagination = collapsibleContainer.querySelector('.table-pagination');
        if (!pagination) {
            pagination = document.createElement('div');
            pagination.className = 'table-pagination';
            collapsibleContainer.appendChild(pagination);
            console.log(`Created pagination div for ${id}`);
        }

        const pageSizeSelect = document.createElement('select');
        pageSizeSelect.setAttribute('aria-label', 'Items per page');
        [10, 25, 50].forEach(n => {
            const opt = document.createElement('option');
            opt.value = n;
            opt.textContent = `${n} per page`;
            if (n === pageSize) opt.selected = true;
            pageSizeSelect.appendChild(opt);
        });

        pageSizeSelect.addEventListener('change', () => {
            pageSize = parseInt(pageSizeSelect.value);
            currentPage = 1;
            totalPages = Math.ceil(dataRows.length / pageSize);
            update();
        });

        function createButton(label, onClick, disabled, active = false) {
            const btn = document.createElement('button');
            btn.textContent = label;
            btn.disabled = disabled;
            if (active) btn.classList.add('active');
            btn.setAttribute('aria-label', label === '←' ? 'Previous page' : label === '→' ? 'Next page' : `Go to page ${label}`);
            btn.addEventListener('click', onClick);
            return btn;
        }

        function createEllipsis() {
            const span = document.createElement('span');
            span.textContent = '...';
            span.style.padding = '6px 12px';
            return span;
        }

        function updatePaginationControls() {
            pagination.innerHTML = '';

            pagination.appendChild(createButton('←', () => {
                if (currentPage > 1) {
                    currentPage--;
                    update();
                }
            }, currentPage === 1));

            let startPage, endPage;
            const halfWindow = Math.floor(maxVisiblePages / 2);

            if (totalPages <= maxVisiblePages) {
                startPage = 1;
                endPage = totalPages;
            } else {
                startPage = Math.max(1, currentPage - halfWindow);
                endPage = startPage + maxVisiblePages - 1;

                if (endPage > totalPages) {
                    endPage = totalPages;
                    startPage = Math.max(1, endPage - maxVisiblePages + 1);
                }
            }

            if (startPage > 1) {
                pagination.appendChild(createButton(1, () => {
                    currentPage = 1;
                    update();
                }, false));
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

            if (endPage < totalPages) {
                if (endPage < totalPages - 1) {
                    pagination.appendChild(createEllipsis());
                }
                pagination.appendChild(createButton(totalPages, () => {
                    currentPage = totalPages;
                    update();
                }, false, currentPage === totalPages));
            }

            pagination.appendChild(createButton('→', () => {
                if (currentPage < totalPages) {
                    currentPage++;
                    update();
                }
            }, currentPage === totalPages));

            pagination.appendChild(pageSizeSelect);

            console.log(`Pagination controls updated for ${id}, page ${currentPage}/${totalPages}, range ${startPage}-${endPage}`);
        }

        function showPage() {
            if (headerRow) {
                headerRow.style.display = '';
            }
            const start = (currentPage - 1) * pageSize;
            const end = start + pageSize;
            dataRows.forEach((row, i) => {
                row.style.display = (i >= start && i < end) ? '' : 'none';
            });
        }

        function update() {
            showPage();
            updatePaginationControls();
        }

        update();
    } catch (e) {
        console.error(`Pagination Error for ${collapsibleContainer.id}:`, e);
    }
}

// Switch Tab Function
function switchTab(tabName) {
    document.querySelectorAll('.tab-content').forEach(tab => {
        tab.classList.remove('active');
    });

    document.querySelectorAll('.tabs .tab').forEach(tab => {
        tab.classList.remove('active');
    });

    document.getElementById(tabName).classList.add('active');

    document.querySelector(`.tabs .tab[data-tab="${tabName}"]`).classList.add('active');

    if (tabName === "events") {
        const eventsContent = document.getElementById('events');
        if (eventsContent) {
            eventsContent.style.animation = "flashHighlight 0.5s ease";
            setTimeout(() => {
                eventsContent.style.animation = "";
            }, 500);
        }
    }
}