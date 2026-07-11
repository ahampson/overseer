const express = require('express');
const session = require('express-session');
const helmet = require('helmet');
const path = require('path');
const pug = require('pug');
const app = express()
const port = process.env.PORT || 8080;
const utils = require('./bin/utilitys');
const db = require('./bin/database');

console.log(`
<#=======================================================#>  
   mmmm                                                  
  m"  "m m   m   mmm    m mm   mmm    mmm    mmm    m mm 
  #    # "m m"  #"  #   #"  " #   "  #"  #  #"  #   #"  "
  #    #  #m#   #""""   #      """m  #""""  #""""   #    
   #mm#    #    "#mm"   #     "mmm"  "#mm"  "#mm"   #   
<#=======================================================#>`)

app.use(session({
  secret: process.env.SESSION_SECRET || 'defaultsecret',
  resave: false,
  saveUninitialized: false
}));
app.use(helmet());

app.set('view engine', 'pug');
app.set('views', path.join(__dirname, 'views'));

app.use(express.static(path.join(__dirname, 'public')));

app.get('/', (req, res) => {
  res.render('index');
});

app.get('/inventory', (req, res) => {
  db.getAllDevices().then(devices => {
      res.render('inventory', { devices });
    }).catch(err => {
      console.error('Error fetching devices:', err);
      res.status(500).render('error', { message: 'Internal Server Error', status: 500 });
    });
});

app.get('/inventory/new', (req, res) => {
  res.render('newDevice');
});

app.get('/alerts', (req, res) => {
  res.render('index');
});

app.get('/settings', (req, res) => {
  res.render('index');
});

app.use((req, res, next) => {
  res.status(404).render('error', { message: 'Page not found', status: 404 });
});

app.listen(port, () => {
    console.log(`Server is running on http://localhost:${port}`);
})