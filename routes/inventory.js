var express = require('express');
var createError = require('http-errors');
var router = express.Router();
const db = require('../bin/database');
var fileUpload = require('express-fileupload')
const bodyParser = require('body-parser');

router.use(fileUpload());
router.use(bodyParser.json());
router.use(bodyParser.urlencoded({ extended: true }));

router.get('/', (req, res) => {
  db.getAllDevices().then(devices => {
      res.render('inventory', { devices });
    }).catch(err => {
      console.error('Error fetching devices:', err);
      res.status(500).render('error', { message: 'Internal Server Error', status: 500 });
    });
});

router.get('/new', (req, res) => {
  res.render('newDevice');
});

router.post('/new', (req, res) => {
  const { deviceName, ipaddress } = req.body;
  db.addDevice({ name: deviceName, ip_address: ipaddress }).then(() => {
      res.redirect('/inventory');
    }).catch(err => {
      console.error('Error adding device:', err);
      res.status(500).render('error', { message: 'Internal Server Error', status: 500 });
    });
});

module.exports = router;