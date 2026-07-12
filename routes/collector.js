var express = require('express');
var createError = require('http-errors');
var router = express.Router();
const db = require('../bin/database');

router.get('/', (req, res) => {
    res.render('collector');
});

router.post('/start', (req, res) =>{
    res.render('start');
});

module.exports = router;