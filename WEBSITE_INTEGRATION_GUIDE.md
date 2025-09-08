# Website Integration Guide for Yuti

This guide shows how to deploy your Cardevia PWA to **fluxpointstudios.com** and add promotional elements for easy user access.

## 🚀 **Deployment Strategies**

### **Option 1: Subdomain Deployment (Recommended)**

Deploy as `bluelight.fluxpointstudios.com` (domain kept for existing infra).

**Advantages:**
- Clean separation from main site
- Easy SSL/HTTPS setup
- Better SEO and analytics tracking
- Independent deployment and updates

**Setup Steps:**
1. **DNS Configuration**: Add CNAME record pointing to your hosting provider
2. **SSL Certificate**: Automatic with most hosting providers
3. **Upload**: Deploy `build/web` contents to subdomain

### **Option 2: Subdirectory Deployment**

Deploy as `fluxpointstudios.com/app/` or `fluxpointstudios.com/cardevia/`

**Advantages:**
- Same domain authority
- Simpler domain management
- Lower cost (no additional hosting)

**Setup Steps:**
1. **Create Directory**: `/app/` or `/cardevia/` on your web server
2. **Upload Files**: Copy `build/web` contents to the directory
3. **Configure Routing**: Ensure your server handles SPA routing

---

## 🌐 **Hosting Platform Deployment**

### **Firebase Hosting (Easiest)**

```bash
# From mobile directory
firebase login
firebase init hosting
# Select your project
# Set public directory: build/web
# Configure as SPA: Yes
firebase deploy
```

**Custom Domain Setup:**
1. Go to Firebase Console → Hosting
2. Add custom domain: `bluelight.fluxpointstudios.com`
3. Follow DNS configuration instructions
4. SSL certificate is automatic

### **Vercel Deployment**

```bash
# From mobile directory
vercel login
vercel --prod
# Follow prompts to set custom domain
```

**Custom Domain:**
1. In Vercel dashboard, go to your project
2. Settings → Domains
3. Add `bluelight.fluxpointstudios.com`
4. Configure DNS as instructed

### **Traditional Web Hosting**

```bash
# Upload build/web contents to your hosting provider
# Via FTP, cPanel, or hosting control panel
```

**Server Configuration Required:**
- Ensure HTTPS is enabled
- Configure server to serve `index.html` for all routes
- Set proper MIME types for all file extensions

---

## 🎨 **Promotional Elements for Your Website**

### **PWA Install Button (HTML/CSS/JavaScript)**

Add this to your main website pages:

```html
<!-- PWA Promotion Section -->
<div class="pwa-promotion">
  <div class="pwa-card">
    <div class="pwa-icon">
      <img src="https://bluelight.fluxpointstudios.com/icons/Icon-192.png" alt="Yuti App" width="64" height="64">
    </div>
    <div class="pwa-content">
      <h3>Launch Cardevia Wallet</h3>
      <p>Your conversational Cardano wallet with AI assistant</p>
      <div class="pwa-buttons">
        <a href="https://bluelight.fluxpointstudios.com" class="pwa-button primary" target="_blank">Open Yuti</a>
        <button class="pwa-button secondary" onclick="showQRCode()">
          📱 Scan QR Code
        </button>
      </div>
    </div>
  </div>
</div>

<!-- QR Code Modal -->
<div id="qr-modal" class="qr-modal" style="display: none;">
  <div class="qr-modal-content">
    <span class="qr-close" onclick="hideQRCode()">&times;</span>
    <h3>Scan to Open Cardevia</h3>
    <div id="qr-code"></div>
    <p>Scan with your phone's camera to open the Cardevia wallet</p>
  </div>
</div>
```

### **CSS Styling**

```css
.pwa-promotion {
  max-width: 500px;
  margin: 2rem auto;
  padding: 1rem;
}

.pwa-card {
  background: linear-gradient(135deg, #0175C2 0%, #1E88E5 100%);
  border-radius: 16px;
  padding: 2rem;
  color: white;
  box-shadow: 0 8px 32px rgba(1, 117, 194, 0.3);
  display: flex;
  align-items: center;
  gap: 1.5rem;
}

.pwa-icon img {
  border-radius: 12px;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.2);
}

.pwa-content h3 {
  margin: 0 0 0.5rem 0;
  font-size: 1.5rem;
  font-weight: 600;
}

.pwa-content p {
  margin: 0 0 1rem 0;
  opacity: 0.9;
}

.pwa-buttons {
  display: flex;
  gap: 0.75rem;
  flex-wrap: wrap;
}

.pwa-button {
  padding: 0.75rem 1.5rem;
  border-radius: 8px;
  text-decoration: none;
  font-weight: 500;
  font-size: 0.9rem;
  transition: all 0.2s ease;
  cursor: pointer;
  border: none;
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
}

.pwa-button.primary {
  background: white;
  color: #0175C2;
}

.pwa-button.primary:hover {
  background: #f8f9fa;
  transform: translateY(-2px);
}

.pwa-button.secondary {
  background: rgba(255, 255, 255, 0.2);
  color: white;
  border: 1px solid rgba(255, 255, 255, 0.3);
}

.pwa-button.secondary:hover {
  background: rgba(255, 255, 255, 0.3);
  transform: translateY(-2px);
}

/* QR Code Modal */
.qr-modal {
  position: fixed;
  z-index: 1000;
  left: 0;
  top: 0;
  width: 100%;
  height: 100%;
  background-color: rgba(0, 0, 0, 0.8);
  display: flex;
  align-items: center;
  justify-content: center;
}

.qr-modal-content {
  background: white;
  padding: 2rem;
  border-radius: 16px;
  text-align: center;
  max-width: 400px;
  position: relative;
}

.qr-close {
  position: absolute;
  top: 1rem;
  right: 1.5rem;
  font-size: 2rem;
  cursor: pointer;
  color: #666;
}

.qr-close:hover {
  color: #000;
}

#qr-code {
  margin: 1rem 0;
  display: flex;
  justify-content: center;
}

/* Responsive Design */
@media (max-width: 768px) {
  .pwa-card {
    flex-direction: column;
    text-align: center;
  }
  
  .pwa-buttons {
    justify-content: center;
  }
}
```

### **JavaScript for QR Code Generation**

```html
<!-- Include QR Code library -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrious/4.0.2/qrious.min.js"></script>

<script>
function showQRCode() {
  const modal = document.getElementById('qr-modal');
  const qrContainer = document.getElementById('qr-code');
  
  // Clear previous QR code
  qrContainer.innerHTML = '';
  
  // Generate QR code
  const qr = new QRious({
    element: document.createElement('canvas'),
    value: 'https://bluelight.fluxpointstudios.com',
    size: 256,
    level: 'H'
  });
  
  qrContainer.appendChild(qr.canvas);
  modal.style.display = 'flex';
}

function hideQRCode() {
  document.getElementById('qr-modal').style.display = 'none';
}

// Close modal when clicking outside
window.onclick = function(event) {
  const modal = document.getElementById('qr-modal');
  if (event.target === modal) {
    hideQRCode();
  }
}

// PWA install prompt handling
let deferredPrompt;

window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();
  deferredPrompt = e;
  
  // Show custom install button if user is on the PWA domain
  if (window.location.hostname.includes('fluxpointstudios.com')) {
    showInstallButton();
  }
});

function showInstallButton() {
  // Add install button to PWA promotion if user can install
  const buttons = document.querySelector('.pwa-buttons');
  if (buttons && !document.querySelector('.install-button')) {
    const installBtn = document.createElement('button');
    installBtn.className = 'pwa-button primary install-button';
    installBtn.innerHTML = '⬇️ Install App';
    installBtn.onclick = installPWA;
    buttons.appendChild(installBtn);
  }
}

async function installPWA() {
  if (deferredPrompt) {
    deferredPrompt.prompt();
    const { outcome } = await deferredPrompt.userChoice;
    console.log(`User response: ${outcome}`);
    deferredPrompt = null;
    
    // Hide install button after installation attempt
    const installBtn = document.querySelector('.install-button');
    if (installBtn) {
      installBtn.style.display = 'none';
    }
  }
}
</script>
```

---

## 📱 **Mobile-Optimized Promotion**

### **Floating Action Button (Mobile)**

For mobile users visiting your main site:

```html
<!-- Mobile FAB -->
  <div class="mobile-fab" onclick="openYuti()">
  <img src="https://bluelight.fluxpointstudios.com/icons/Icon-192.png" alt="Yuti" width="24" height="24">
  <span>Wallet</span>
</div>

<style>
.mobile-fab {
  position: fixed;
  bottom: 2rem;
  right: 2rem;
  background: #0175C2;
  color: white;
  border-radius: 50px;
  padding: 1rem 1.5rem;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  cursor: pointer;
  box-shadow: 0 8px 24px rgba(1, 117, 194, 0.4);
  z-index: 1000;
  transition: all 0.3s ease;
}

.mobile-fab:hover {
  transform: translateY(-4px);
  box-shadow: 0 12px 32px rgba(1, 117, 194, 0.5);
}

.mobile-fab img {
  border-radius: 4px;
}

@media (min-width: 769px) {
  .mobile-fab {
    display: none;
  }
}
</style>

<script>
function openYuti() {
  window.open('https://bluelight.fluxpointstudios.com', '_blank');
}
</script>
```