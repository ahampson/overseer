var express = require('express');
var createError = require('http-errors');
var router = express.Router();
const db = require('../bin/database');

router.get('/', (req, res) => {
    res.render('collector');
});

module.exports = router;