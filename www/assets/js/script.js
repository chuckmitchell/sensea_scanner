document.addEventListener('DOMContentLoaded', () => {
    const staffGrid = document.getElementById('staff-grid');
    const lastUpdatedEl = document.getElementById('last-updated');

    fetch('appointments.json')
        .then(response => {
            if (!response.ok) {
                throw new Error('Network response was not ok');
            }
            return response.json();
        })
        .then(data => {
            renderStaff(data);
            updateTimestamp();
        })
        .catch(error => {
            console.error('Error fetching data:', error);
            staffGrid.innerHTML = `
                <div class="loading-state">
                    <p>Could not load appointments.</p>
                    <p style="font-size: 0.9rem; margin-top: 10px;">Ensure <code>appointments.json</code> exists by running the scanner script.</p>
                </div>
            `;
        });

    function renderStaff(data) {
        staffGrid.innerHTML = ''; // Clear loading state

        // 1. Flatten data into a list of appointments
        const appointments = [];

        Object.keys(data).forEach(staffName => {
            const staff = data[staffName];
            if (staff.slots && staff.slots.length > 0) {
                staff.slots.forEach(slot => {
                    // slot is [date, time, spots]
                    appointments.push({
                        date: slot[0], // "December 04, 2025"
                        time: slot[1], // "10:30 AM"
                        spots: slot[2], // 7 or null
                        staffName: staffName,
                        staffImage: staff.image_url,
                        staffDesc: staff.description,
                        bookingUrl: staff.booking_url
                    });
                });
            }
        });

        if (appointments.length === 0) {
            staffGrid.innerHTML = '<div class="loading-state"><p>No available slots found in the next 2 weeks.</p></div>';
            return;
        }

        // 2. Group by Date
        // Use a Map to keep insertion order if we sort keys later, but object is fine too
        const appointmentsByDate = {};

        appointments.forEach(appt => {
            if (!appointmentsByDate[appt.date]) {
                appointmentsByDate[appt.date] = [];
            }
            appointmentsByDate[appt.date].push(appt);
        });

        // 3. Sort Dates
        const sortedDates = Object.keys(appointmentsByDate).sort((a, b) => new Date(a) - new Date(b));

        // 4. Render
        sortedDates.forEach(dateStr => {
            // Sort appointments within the day by time
            const dayAppts = appointmentsByDate[dateStr].sort((a, b) => {
                // Parse time "10:30 AM"
                const timeA = parseTime(a.time);
                const timeB = parseTime(b.time);
                return timeA - timeB;
            });

            // Create Date Section
            const section = document.createElement('section');
            section.className = 'date-section';

            // Format nice date header: "Monday, December 4th"
            const dateObj = new Date(dateStr);
            const niceDate = dateObj.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });

            section.innerHTML = `<h2 class="date-header">${niceDate}</h2>`;

            const grid = document.createElement('div');
            grid.className = 'appointments-grid';

            dayAppts.forEach(appt => {
                const tile = document.createElement('div');
                tile.className = 'appt-tile';

                // Extract type from name if present "Name (Type)"
                let displayName = appt.staffName;
                let typeBadge = '';
                const typeMatch = appt.staffName.match(/(.*)\s\((.*)\)$/);
                if (typeMatch) {
                    displayName = typeMatch[1];
                    typeBadge = `<span class="type-badge">${typeMatch[2]}</span>`;
                } else if (appt.staffName === 'Spa Pass') {
                    typeBadge = `<span class="type-badge spa-pass">Spa Pass</span>`;
                }

                // Spots badge
                let spotsBadge = '';
                if (appt.spots) {
                    const spotsClass = appt.spots <= 2 ? 'spots-low' : 'spots-ok';
                    spotsBadge = `<div class="spots-badge ${spotsClass}">${appt.spots} Spots Left</div>`;
                }

                let imageUrl = appt.staffImage;

                if (appt.staffName === 'Spa Pass') {
                    imageUrl = 'assets/img/spa_pass.png';
                } else if (appt.staffName.includes('(Couples)')) {
                    imageUrl = 'assets/img/couples_massage.png';
                } else if (imageUrl && imageUrl.startsWith('//')) {
                    imageUrl = 'https:' + imageUrl;
                } else if (!imageUrl) {
                    imageUrl = 'https://via.placeholder.com/100?text=No+Img';
                }
                const bookingUrl = appt.bookingUrl || '#';

                tile.innerHTML = `
                    <a href="${bookingUrl}" target="_blank" class="tile-link">
                        <div class="tile-left">
                            <img src="${imageUrl}" alt="${displayName}" class="tile-thumb">
                        </div>
                        <div class="tile-right">
                            <div class="tile-time">${appt.time}</div>
                            <div class="tile-name">${displayName}</div>
                            ${typeBadge}
                            ${spotsBadge}
                        </div>
                    </a>
                `;

                grid.appendChild(tile);
            });

            section.appendChild(grid);
            staffGrid.appendChild(section);
        });
    }

    function parseTime(timeStr) {
        const [time, modifier] = timeStr.split(' ');
        let [hours, minutes] = time.split(':');
        if (hours === '12') {
            hours = '00';
        }
        if (modifier === 'PM') {
            hours = parseInt(hours, 10) + 12;
        }
        return new Date(2000, 0, 1, hours, minutes);
    }

    function updateTimestamp() {
        const now = new Date();
        lastUpdatedEl.textContent = `Last updated: ${now.toLocaleTimeString()} on ${now.toLocaleDateString()}`;
    }
});
