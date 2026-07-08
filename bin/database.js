const sqlite3 = require('sqlite3').verbose();
const utils = require('./utilitys');

utils.loadEnvFile();

const db = new sqlite3.Database(process.env.DATABASE_URL.replace('sqlite://', ''));

function getAllDevices() {
    return new Promise((resolve, reject) => {
        db.all('SELECT * FROM Devices_Table ORDER BY Name', [], (err, rows) => {
            if (err) {
                reject(err);
            } else {
                resolve(rows);
            }
        });
    });
}

module.exports = {
    getAllDevices
};