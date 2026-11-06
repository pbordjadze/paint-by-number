const {chromium}=require('playwright');
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:402,height:874},deviceScaleFactor:3});
for(const n of ['a','b','c']){await p.goto('file://'+process.cwd()+'/'+n+'.html');await p.waitForTimeout(300);await p.screenshot({path:'mock-'+n+'.png'});}
await b.close();})();
