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

function addDevice(device) {
    return new Promise((resolve, reject) => {
        const { Name, IP_Address, Status } = device;
        db.run('INSERT INTO Devices_Table (Name, IP_Address, Status) VALUES (?, ?, ?)', [Name, IP_Address, Status], function(err) {
            if (err) {
                reject(err);
            } else {
                resolve(this.lastID);
            }
        });
    });
}

function addDeviceType(deviceType) {
    return new Promise((resolve, reject) => {
        const { TypeName, Description, Ports } = deviceType;
        db.run('INSERT INTO DeviceTypes_Table (TypeName, Description, Ports) VALUES (?, ?, ?)', [TypeName, Description, Ports], function(err) {
            if (err) {
                reject(err);
            } else {
                resolve(this.lastID);
            }
        });
    });
}    

module.exports = {
    getAllDevices,
    addDevice,
    addDeviceType
};