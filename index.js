const express = require('express')
const app = express()
const port = 3000

app.get('/', (req, res) => res.send('Hello from Terraform demo!'))

app.listen(port, () => console.log(`Terraform demo listening on port ${port}`))