const fs = require('fs');
const crypto = require('crypto');

// Read the .env.example file
let env = fs.readFileSync('.env.example', 'utf8');

// Replace placeholder with a generated secret
env = env.replace('__GENERATE__', crypto.randomBytes(64).toString('hex'));

fs.writeFileSync('.env', env);
console.log('✔ .env created with generated values');