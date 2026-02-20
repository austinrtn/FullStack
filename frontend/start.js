const express = require("express");
const app = express();
app.use(express.json());

let client = null;

app.get('/', (req, res) => {
	res.sendFile(__dirname + '/index.html');
});

app.get('/display', (req, res) => {
	res.sendFile(__dirname + '/display.html');
});

app.listen(3000, '0.0.0.0', ()=>{
	console.log("Listening to 3000");
});

