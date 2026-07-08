const fs = require('fs');
const crypto = require('crypto');
const path = require('path');
const utils = require('./utilitys');

console.log('<#=======================================================#>');
console.log(' Overseer Build Script Started:', new Date().toLocaleString());
console.log('<#=======================================================#>');

if(utils.createEnvFile()){
    console.log('✔ .env created with generated values');
    utils.loadEnvFile();
}else{
    console.log('✖ Failed to create .env file');
};

if(utils.initializeDatabase(process.env.DATABASE_URL.replace('sqlite://', ''))){
    console.log('✔ Database initialized');
}else{
    console.log('✖ Failed to initialize database');
};
