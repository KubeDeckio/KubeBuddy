// Back to Top
window.addEventListener('scroll', function () {
    const button = document.getElementById('backToTop');
    if (button) button.style.display = window.scrollY > 200 ? 'block' : 'none';
});

// Global print state
let isPrinting = false;

document.addEventListener('DOMContentLoaded', function () {
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

    // Save as PDF
    try {
        const savePdfBtn = document.getElementById('savePdfBtn');
        if (!savePdfBtn) {
            console.error('Save PDF button not found');
        } else {
            savePdfBtn.addEventListener('click', function () {
                isPrinting = true;
                console.log('Preparing for PDF: expanding details and removing pagination');

                document.querySelectorAll('.table-pagination').forEach(pagination => {
                    console.log(`Pre-print: Removing pagination from ${pagination.parentElement.id}`);
                    pagination.remove();
                });

                const detailsElements = document.querySelectorAll('details');
                const detailsStates = new Map();
                detailsElements.forEach(detail => {
                    detailsStates.set(detail, detail.open);
                    detail.open = true;
                });

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

                document.querySelectorAll('.collapsible-container').forEach(container => {
                    const table = container.querySelector('table');
                    if (table) {
                        const allRows = Array.from(table.querySelectorAll('tr')).filter(row => row.cells.length > 0);
                        console.log(`Pre-print: Showing all ${allRows.length - 1} rows for ${container.id}`);
                        allRows.forEach(row => row.style.display = '');
                    }
                });

                setTimeout(() => {
                    window.print();
                }, 1500);

                window.onafterprint = function () {
                    console.log('PDF print complete, restoring original state');
                    isPrinting = false;
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
                };
            });

            window.addEventListener('afterprint', () => {
                if (isPrinting) {
                    isPrinting = false;
                    console.log('Print canceled, restoring pagination');
                    document.querySelectorAll('.collapsible-container').forEach(container => {
                        if (container.querySelector('details').open) {
                            paginateTable(container);
                        }
                    });
                }
            });
        }
    } catch (e) {
        console.error('PDF Error:', e);
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

                // Initialize sorting state for this table
                collapsibleContainer.sortState = {
                    columnIndex: null,
                    ascending: true
                };

                detail.addEventListener('toggle', () => {
                    summary.textContent = detail.open ? 'Hide Findings' : defaultText;
                    const pagination = collapsibleContainer.querySelector('.table-pagination');
                
                    if (detail.open) {
                        console.log(`Toggled open: ${id}, calling paginateTable`);
                        setTimeout(() => paginateTable(collapsibleContainer), 200);
                    } else if (pagination) {
                        pagination.remove();
                        console.log(`Toggled closed: ${id}, removed pagination`);
                    }
                });

                // Add sorting functionality to table headers
                const table = collapsibleContainer.querySelector('table');
                if (table) {
                    const headers = table.querySelectorAll('th');
                    headers.forEach((header, index) => {
                        header.style.cursor = 'pointer'; // Make header clickable
                        header.addEventListener('click', () => {
                            sortTable(collapsibleContainer, index);
                            paginateTable(collapsibleContainer); // Re-paginate after sorting
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

        // Determine sort direction
        const sortState = collapsibleContainer.sortState;
        if (sortState.columnIndex === columnIndex) {
            sortState.ascending = !sortState.ascending; // Toggle direction
        } else {
            sortState.columnIndex = columnIndex;
            sortState.ascending = true;
        }

        // Update header to show sort direction
        const headers = table.querySelectorAll('th');
        headers.forEach((header, idx) => {
            header.innerHTML = header.innerHTML.replace(/ (↑|↓)$/, ''); // Remove existing arrows
            if (idx === columnIndex) {
                header.innerHTML += sortState.ascending ? ' ↑' : ' ↓'; // Add arrow
            }
        });

        // Sort the rows
        dataRows.sort((rowA, rowB) => {
            let cellA = rowA.cells[columnIndex].textContent.trim();
            let cellB = rowB.cells[columnIndex].textContent.trim();

            // Handle special cases for specific columns (e.g., Status, Severity)
            if (columnIndex === 4 && cellA.includes('PASS') && cellB.includes('FAIL')) {
                return sortState.ascending ? -1 : 1;
            } else if (columnIndex === 4 && cellA.includes('FAIL') && cellB.includes('PASS')) {
                return sortState.ascending ? 1 : -1;
            }

            if (columnIndex === 2) { // Severity column
                const severityOrder = { 'High': 3, 'Medium': 2, 'Low': 1 };
                const valA = severityOrder[cellA] || 0;
                const valB = severityOrder[cellB] || 0;
                return sortState.ascending ? valA - valB : valB - valA;
            }

            // Default sorting (alphabetical or numerical)
            const isNumeric = !isNaN(parseFloat(cellA)) && !isNaN(parseFloat(cellB));
            if (isNumeric) {
                return sortState.ascending ? parseFloat(cellA) - parseFloat(cellB) : parseFloat(cellB) - parseFloat(cellA);
            } else {
                return sortState.ascending ? cellA.localeCompare(cellB) : cellB.localeCompare(cellA);
            }
        });

        // Rebuild the table body with sorted rows
        const tbody = table.querySelector('tbody') || table;
        dataRows.forEach(row => tbody.appendChild(row));

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
        const maxVisiblePages = 5; // Window of 5 pages

        let pagination = collapsibleContainer.querySelector('.table-pagination');
        if (!pagination) {
            pagination = document.createElement('div');
            pagination.className = 'table-pagination';
            collapsibleContainer.appendChild(pagination);
            console.log(`Created pagination div for ${id}`);
        }

        const pageSizeSelect = document.createElement('select');
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

            // Previous Button
            pagination.appendChild(createButton('←', () => {
                if (currentPage > 1) {
                    currentPage--;
                    update();
                }
            }, currentPage === 1));

            // Calculate the range of pages to display
            let startPage, endPage;
            const halfWindow = Math.floor(maxVisiblePages / 2);

            if (totalPages <= maxVisiblePages) {
                // If total pages are less than or equal to the window size, show all pages
                startPage = 1;
                endPage = totalPages;
            } else {
                // Center the current page in the window
                startPage = Math.max(1, currentPage - halfWindow);
                endPage = startPage + maxVisiblePages - 1;

                // Adjust if the end page exceeds total pages
                if (endPage > totalPages) {
                    endPage = totalPages;
                    startPage = Math.max(1, endPage - maxVisiblePages + 1);
                }
            }

            // Add ellipsis before if there are pages before startPage
            if (startPage > 1) {
                pagination.appendChild(createButton(1, () => {
                    currentPage = 1;
                    update();
                }, false));
                if (startPage > 2) {
                    pagination.appendChild(createEllipsis());
                }
            }

            // Show the page numbers in the calculated range
            for (let i = startPage; i <= endPage; i++) {
                pagination.appendChild(createButton(i, () => {
                    currentPage = i;
                    update();
                }, false, i === currentPage));
            }

            // Add ellipsis after and last page if there are pages after endPage
            if (endPage < totalPages) {
                if (endPage < totalPages - 1) {
                    pagination.appendChild(createEllipsis());
                }
                pagination.appendChild(createButton(totalPages, () => {
                    currentPage = totalPages;
                    update();
                }, false, currentPage === totalPages));
            }

            // Next Button
            pagination.appendChild(createButton('→', () => {
                if (currentPage < totalPages) {
                    currentPage++;
                    update();
                }
            }, currentPage === totalPages));

            // Page Size Selector
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