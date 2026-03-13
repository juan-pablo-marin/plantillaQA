const http = require('http');
const fs = require('fs');

const auth = 'Basic ' + Buffer.from('admin:admin').toString('base64');
const jenkinsfile = fs.readFileSync('Jenkinsfile', 'utf8');

const reqOptions = {
  hostname: 'localhost',
  port: 8085,
  path: '/job/Ficha-Caracterizacion-Pipeline-QA/config.xml',
  method: 'GET',
  headers: { 'Authorization': auth }
};

const req = http.request(reqOptions, (res) => {
  let data = '';
  res.on('data', (c) => data += c);
  res.on('end', () => {
    // Replace the script content
    const startScript = data.indexOf('<script>');
    const endScript = data.indexOf('</script>');
    if (startScript === -1 || endScript === -1) {
        console.log('Error: <script> tag not found');
        return;
    }
    
    // HTML escape
    const escapeHTML = str => str.replace(/[&<>'"]/g, 
        tag => ({
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            "'": '&#39;',
            '"': '&quot;'
        }[tag]));
    
    const newXml = data.substring(0, startScript + 8) + escapeHTML(jenkinsfile) + data.substring(endScript);
    
    // Now get crumb
    http.request({
        hostname: 'localhost', port: 8085, path: '/crumbIssuer/api/json', method: 'GET', headers: { 'Authorization': auth }
    }, (res2) => {
        let crumbData = '';
        res2.on('data', c => crumbData += c);
        res2.on('end', () => {
            const crumb = JSON.parse(crumbData);
            const postHeaders = {
                'Authorization': auth,
                'Content-Type': 'application/xml',
                [crumb.crumbRequestField]: crumb.crumb
            };
            
            // Note: need cookie from res2
            if (res2.headers['set-cookie']) {
                postHeaders['Cookie'] = res2.headers['set-cookie'].join(';');
            }
            
            const postReq = http.request({
                hostname: 'localhost', port: 8085, path: '/job/Ficha-Caracterizacion-Pipeline-QA/config.xml', method: 'POST', headers: postHeaders
            }, (res3) => {
                console.log('Status:', res3.statusCode);
            });
            postReq.write(newXml);
            postReq.end();
        });
    }).end();
  });
});
req.end();
