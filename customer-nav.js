(function(){
  var isNative=window.Capacitor
    &&typeof window.Capacitor.isNativePlatform==='function'
    &&window.Capacitor.isNativePlatform();
  if(!isNative&&!window.matchMedia('(max-width: 640px)').matches)return;
  if(document.querySelector('.dock'))return;

  var links=[
    {label:'Home',href:'/',paths:['/']},
    {label:'Booking',href:'/booking.html',paths:['/booking.html']},
    {label:'Member',href:'/account.html#membership',paths:['/account.html'],hash:'#membership'},
    {label:'Riwayat',href:'/account.html#booking-history',paths:['/account.html'],hash:'#booking-history'}
  ];
  var path=window.location.pathname;
  var hash=window.location.hash;
  var nav=document.createElement('div');
  nav.className='customer-bottom-nav';
  nav.setAttribute('role','navigation');
  nav.setAttribute('aria-label','Navigasi pelanggan');

  links.forEach(function(link){
    var item=document.createElement('a');
    item.href=link.href;
    item.textContent=link.label;
    if(link.paths.includes(path)&&(!link.hash||link.hash===hash||!hash&&link.hash==='#membership')){
      item.setAttribute('aria-current','page');
    }
    nav.append(item);
  });

  var style=document.createElement('style');
  style.textContent='.customer-bottom-nav{position:fixed;z-index:1000;inset:auto 0 0;display:grid;grid-template-columns:repeat(4,1fr);padding:8px 8px calc(8px + env(safe-area-inset-bottom));border-top:1px solid #2e2820;background:#0b0a09f5;backdrop-filter:blur(14px)}.customer-bottom-nav a{min-height:44px;display:grid;place-items:center;color:#a39a8c;text-decoration:none;font:500 11px/1.2 Poppins,system-ui,sans-serif}.customer-bottom-nav a[aria-current=page]{color:#d4a86a}.customer-bottom-nav[hidden]{display:none}body{padding-bottom:calc(68px + env(safe-area-inset-bottom))}';
  document.head.append(style);
  document.body.append(nav);
  window.setCustomerNavigationVisible=function(visible){nav.hidden=!visible};
})();
