# DNS Setup Guide for bluelight.fluxpointstudios.com

## 🌐 **Subdomain Configuration**

Based on your existing DNS records, you'll need to add a new record for the BlueLight PWA subdomain.

## 🔧 **DNS Record Setup**

### **Option 1: CNAME Record (Recommended for hosting platforms)**

For **Firebase Hosting**, **Vercel**, or **Netlify**:

```
HOST: bluelight
TYPE: CNAME
TTL: 4 hrs (or your preferred TTL)
DATA: [Your hosting platform's domain]
```

**Examples:**
- **Firebase**: `bluelight.fluxpointstudios.com.web.app`
- **Vercel**: `cname.vercel-dns.com`
- **Netlify**: `[your-site-name].netlify.app`

### **Option 2: A Record (For direct IP hosting)**

If hosting on a server with static IP:

```
HOST: bluelight
TYPE: A
TTL: 4 hrs
DATA: [Your server IP address]
```

## 🚀 **Platform-Specific Setup**

### **Firebase Hosting**

1. **Deploy PWA to Firebase:**
   ```bash
   cd mobile
   firebase login
   firebase init hosting
   # Set public directory: build/web
   firebase deploy
   ```

2. **Add Custom Domain:**
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Select your project → Hosting
   - Click "Add custom domain"
   - Enter: `bluelight.fluxpointstudios.com`
   - Follow DNS instructions (usually CNAME)

3. **DNS Record:**
   ```
   HOST: bluelight
   TYPE: CNAME
   DATA: bluelight.fluxpointstudios.com.web.app
   ```

### **Vercel**

1. **Deploy PWA to Vercel:**
   ```bash
   cd mobile
   vercel login
   vercel --prod
   ```

2. **Add Custom Domain:**
   - Go to [Vercel Dashboard](https://vercel.com/dashboard)
   - Select your project → Settings → Domains
   - Add: `bluelight.fluxpointstudios.com`
   - Follow DNS instructions

3. **DNS Record:**
   ```
   HOST: bluelight
   TYPE: CNAME
   DATA: cname.vercel-dns.com
   ```

### **Netlify**

1. **Deploy PWA to Netlify:**
   ```bash
   cd mobile
   # Build first
   flutter build web --release --pwa-strategy offline-first
   # Deploy build/web folder via Netlify dashboard or CLI
   ```

2. **Add Custom Domain:**
   - Go to Netlify dashboard
   - Site settings → Domain management
   - Add custom domain: `bluelight.fluxpointstudios.com`

3. **DNS Record:**
   ```
   HOST: bluelight
   TYPE: CNAME
   DATA: [your-netlify-site].netlify.app
   ```

## ✅ **Verification Steps**

### **1. DNS Propagation Check**
```bash
# Check DNS resolution
nslookup bluelight.fluxpointstudios.com

# Or use online tools
# https://dnschecker.org
```

### **2. SSL Certificate Verification**
```bash
# Check SSL certificate
curl -I https://bluelight.fluxpointstudios.com
```

### **3. PWA Functionality Test**
- Visit `https://bluelight.fluxpointstudios.com`
- Check service worker registration (DevTools → Application)
- Test offline functionality
- Verify install prompts on mobile

## 📊 **Expected DNS Table After Setup**

Your DNS records should look like this:

```
HOST              TYPE    TTL      DATA
adam-dashboard    A       5 mins   161.35.253.78
api              A       30 mins   68.183.117.216
bluelight        CNAME   4 hrs    [hosting-platform-domain]
bounce           CNAME   4 hrs    custom-email-domain.stripe.com
_dmarc           TXT     4 hrs    v=DMARC1; p=quarantine
docs             CNAME   4 hrs    e794a5f204-hosting.gitbook.io
@                A       4 hrs    76.76.21.21
@                MX      20       mailsec.protonmail.ch
@                MX      10       mail.protonmail.ch
```

## 🔍 **Troubleshooting**

### **Common Issues**

1. **DNS Not Propagating**
   - Wait 5-15 minutes for changes
   - Check TTL settings (lower = faster updates)
   - Clear DNS cache: `ipconfig /flushdns` (Windows)

2. **SSL Certificate Issues**
   - Ensure DNS is pointing correctly first
   - Most hosting platforms auto-generate SSL
   - Wait 5-10 minutes after DNS propagation

3. **PWA Not Loading**
   - Check if files deployed correctly
   - Verify HTTPS is working
   - Check browser console for errors

### **Testing Commands**

```bash
# Test DNS resolution
nslookup bluelight.fluxpointstudios.com

# Test HTTPS
curl -I https://bluelight.fluxpointstudios.com

# Test PWA manifest
curl https://bluelight.fluxpointstudios.com/manifest.json

# Lighthouse PWA audit
lighthouse https://bluelight.fluxpointstudios.com --only-categories=pwa
```

## 🎯 **Next Steps**

1. **Add DNS record** for `bluelight` subdomain
2. **Deploy PWA** to your chosen hosting platform
3. **Configure custom domain** in hosting platform
4. **Wait for propagation** (5-15 minutes)
5. **Test PWA** at `https://bluelight.fluxpointstudios.com`
6. **Update website** `/bluelight` page is ready to go!

Your BlueLight PWA will be accessible at its own professional subdomain! 🚀 