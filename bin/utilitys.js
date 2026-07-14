const fs = require('fs');
const crypto = require('crypto');
const sqlite3 = require('sqlite3').verbose();

function generateSecret() {
  return crypto.randomBytes(64).toString('hex');
}

function createEnvFile() {
  // Read the .env.example file
  let env = fs.readFileSync('.env.example', 'utf8');
  
  // Replace placeholder with a generated secret
  env = env.replace('__GENERATE__', generateSecret());
  
  fs.writeFileSync('.env', env);

  return true;
}

function loadEnvFile() {
    if (fs.existsSync('.env')) {
        const env = fs.readFileSync('.env', 'utf8');
        env.split('\n').forEach(line => {
        const [key, value] = line.split('=');
            if (key && value) { 
                process.env[key.trim()] = value.trim();
            }
        });
    }
}

async function initializeDatabase(filePath) {
    const db = new sqlite3.Database(filePath, (err) => {
        if (err) {
            console.error('Error opening database:', err.message);
            return false;
        } else {
            console.log('Connected to the SQLite database:', filePath);
            db.run(`CREATE TABLE IF NOT EXISTS Devices_Table ( 
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                Name TEXT UNIQUE NOT NULL,
                IPAddress TEXT NOT NULL,
                Status TEXT NOT NULL,
                LastUpdated TEXT NOT NULL
            )`);
            db.run(`CREATE TABLE IF NOT EXISTS StatusCollector_Table (
                id INTEGER PRIMARY KEY,
                Status TEXT NOT NULL,
                ProcessID INTEGER UNIQUE NOT NULL
            )`);
        }
    });
    return true;
}

module.exports = {
    generateSecret,
    createEnvFile,
    loadEnvFile,
    initializeDatabase,
};