var express = require('express');
var createError = require('http-errors');
var router = express.Router();
const db = require('../bin/database');
const { spawn } = require('node:child_process');

router.get('/', (req, res) => {
    res.render('collector');
});

router.post('/start', (req, res) =>{
    const statusCollector = spawn("Powershell", ["./bin/StatusCollector.ps1"]);
    // Listen for standard output data chunks
    statusCollector.stdout.on('data', (data) => {
        console.log(`stdout: ${data}`);
    });

    // Listen for standard error chunks
    statusCollector.stderr.on('data', (data) => {
        console.error(`stderr: ${data}`);
    });

    // Triggered when the process terminates completely
    statusCollector.on('close', (code) => {
        console.log(`Child process exited with code ${code}`);
    });

    // Essential error handling to prevent application crashes
    statusCollector.on('error', (err) => {
        console.error('Failed to start child process:', err);
    });
    res.render('start');
});

module.exports = router;