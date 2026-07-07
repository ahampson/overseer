const express = require('express');
const session = require('express-session');
const helmet = require('helmet');
const path = require('path');
const pug = require('pug');
const app = express()
const port = process.env.PORT || 8080;

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

app.listen(port, () => {
    console.log(`Server is running on http://localhost:${port}`);
})