# BlueLight CI/CD Deployment Guide

**Last Updated:** 7/16/2025 10:24 MST  
**Status:** Production Ready ✅

## 🎯 **Deployment Strategy Overview**

BlueLight uses a **Local Build + Static Serving** deployment strategy due to Vercel's limitations with Flutter web apps.

```
Local Development → Flutter Build → Git Commit → Vercel Static Hosting
```

### Why This Approach?

1. **Vercel Limitation**: Vercel's build environment doesn't include Flutter SDK
2. **Build Consistency**: Local builds ensure consistent environment and dependencies
3. **Pre-built Assets**: Faster deployments since no build step is needed on Vercel
4. **Full Control**: Complete control over build flags and optimizations

---

## 🚀 **Quick Deployment**

### Automated Scripts (Recommended)

**Linux/Mac:**
```bash
# Make script executable (first time only)
chmod +x build-and-deploy.sh

# Deploy with auto-generated commit message
./build-and-deploy.sh

# Deploy with custom commit message
./build-and-deploy.sh "Added GameChanger wallet integration"
```

**Windows:**
```cmd
# Deploy with auto-generated commit message
build-and-deploy.bat

# Deploy with custom commit message
build-and-deploy.bat "Added GameChanger wallet integration"
```

### Manual Process

```bash
# 1. Clean and prepare
flutter clean
flutter pub get

# 2. Build for web with PWA optimizations
flutter build web --release --pwa-strategy offline-first

# 3. Commit and deploy
git add .
git commit -m "🚀 Deploy: Your message here"
git push
```

---

## 🔧 **Configuration Files**

### `package.json`
```json
{
  "scripts": {
    "build": "echo 'Serving pre-built Flutter web files from build/web directory'"
  }
}
```
**Why:** Vercel can't run `flutter build`, so we serve pre-built files.

### `vercel.json`
```json
{
  "outputDirectory": "build/web",
  "rewrites": [
    {
      "source": "/(.*)",
      "destination": "/index.html"
    }
  ]
}
```
**Why:** Configures Vercel to serve Flutter's single-page app correctly.

### `.gitignore`
```
/build/
# Exceptions to the build rule
!/build/web/
```
**Why:** Excludes build files but includes `build/web/` for deployment.

---

## 📋 **Step-by-Step Process**

### 1. Development Phase
- Code changes in `lib/`, `assets/`, etc.
- Test locally: `flutter run -d chrome`
- Commit source code changes

### 2. Build Phase
```bash
flutter clean                    # Clean previous builds
flutter pub get                  # Get latest dependencies
flutter build web --release --pwa-strategy offline-first
```

### 3. Deployment Phase
```bash
git add .                        # Stage build files
git commit -m "🚀 Deploy: ..."   # Commit with descriptive message
git push                         # Trigger Vercel deployment
```

### 4. Verification
- Check Vercel dashboard for deployment status
- Test deployed app functionality
- Verify GameChanger wallet integration

---

## 🛠 **Build Configuration**

### Flutter Build Command
```bash
flutter build web --release --pwa-strategy offline-first
```

**Flags Explained:**
- `--release`: Production build with optimizations
- `--pwa-strategy offline-first`: PWA with offline capabilities
- Result: Creates `build/web/` directory with deployable files

### Build Output Structure
```
build/web/
├── index.html              # Main app file
├── manifest.json           # PWA manifest
├── favicon.png             # App icon
├── icons/                  # PWA icons
├── assets/                 # App assets
├── canvaskit/              # Flutter web renderer
└── flutter_service_worker.js  # Service worker
```

---

## 🔍 **Troubleshooting**

### Common Issues

#### 1. "flutter: command not found"
**Problem:** Flutter not in PATH or not installed  
**Solution:** Install Flutter and add to PATH

#### 2. "No changes to commit"
**Problem:** Build output unchanged  
**Solution:** This is normal if no code changes were made

#### 3. Vercel deployment fails
**Problem:** Missing or corrupted build files  
**Solution:** Run `flutter clean` and rebuild

#### 4. PWA not working
**Problem:** Service worker or manifest issues  
**Solution:** Check `manifest.json` and service worker registration

### Debug Commands

```bash
# Check Flutter installation
flutter doctor

# Verify build output
ls -la build/web/

# Check git status
git status

# View Vercel logs
# (Check Vercel dashboard)
```

---

## 🎯 **Best Practices**

### Commit Messages
Use descriptive commit messages for deployments:
```bash
git commit -m "🚀 Deploy: Add GameChanger wallet integration"
git commit -m "🚀 Deploy: Fix PWA offline caching"
git commit -m "🚀 Deploy: Update UI components"
```

### Pre-Deployment Checklist
- [ ] Test locally: `flutter run -d chrome`
- [ ] Run tests: `flutter test`
- [ ] Check for lint errors: `flutter analyze`
- [ ] Verify GameChanger wallet integration
- [ ] Check PWA functionality

### Deployment Frequency
- **Development:** Deploy frequently for testing
- **Production:** Deploy stable, tested builds
- **Hotfixes:** Use emergency deployment process

---

## 🔄 **CI/CD Pipeline Details**

### Current Workflow
```mermaid
graph LR
    A[Code Changes] --> B[Local Build]
    B --> C[Git Commit]
    C --> D[Git Push]
    D --> E[Vercel Deployment]
    E --> F[Live App]
```

### Disabled GitHub Actions
Previous GitHub Actions workflows were disabled to prevent conflicts:
- `.github/workflows/deploy.yml` - Disabled (manual trigger only)
- `.github/workflows/deploy-web.yml` - Removed

**Why:** Eliminated dual deployment conflicts between GitHub Actions and Vercel.

### Future Enhancements
Potential improvements:
1. **Automated Testing**: Add test runner to deployment scripts
2. **Environment Variables**: Separate dev/prod builds
3. **Rollback System**: Quick revert mechanism
4. **Performance Monitoring**: Lighthouse CI integration

---

## 📊 **Deployment Monitoring**

### Vercel Dashboard
Monitor deployments at: https://vercel.com/dashboard
- Deployment status and logs
- Performance metrics
- Error tracking

### Key Metrics to Watch
- **Build Time**: Should be fast (static serving)
- **Bundle Size**: Monitor for size increases
- **Performance**: Core Web Vitals scores
- **Error Rate**: Track deployment failures

---

## 🚨 **Emergency Procedures**

### Rollback Process
If deployment fails:
```bash
# 1. Revert to previous commit
git log --oneline | head -5    # Find previous working commit
git reset --hard [commit-hash] # Revert to working version
git push --force-with-lease    # Force push (use carefully)
```

### Hotfix Process
For critical fixes:
```bash
# 1. Create hotfix branch
git checkout -b hotfix/critical-fix

# 2. Make minimal changes
# ... edit files ...

# 3. Test and deploy
flutter build web --release
git add .
git commit -m "🚨 Hotfix: Critical issue fix"
git checkout main
git merge hotfix/critical-fix
git push
```

---

## 📚 **Reference Documentation**

### Related Files
- `build-and-deploy.sh` - Linux/Mac deployment script
- `build-and-deploy.bat` - Windows deployment script
- `vercel.json` - Vercel configuration
- `package.json` - Build script configuration
- `.gitignore` - Git ignore rules

### External Resources
- [Flutter Web Documentation](https://docs.flutter.dev/platform-integration/web)
- [Vercel Documentation](https://vercel.com/docs)
- [PWA Best Practices](https://web.dev/progressive-web-apps/)
- [GameChanger Wallet Integration](https://github.com/GameChangerFinance/gamechanger)

---

## ✅ **Success Criteria**

A successful deployment should:
- [ ] Build completes without errors
- [ ] All required files present in `build/web/`
- [ ] Git push succeeds
- [ ] Vercel deployment shows "Ready"
- [ ] App loads correctly at deployed URL
- [ ] GameChanger wallet integration works
- [ ] PWA features functional

---

**🎉 Happy Deploying!**

*This guide documents the lessons learned from resolving dual deployment conflicts and establishing a reliable Flutter web deployment pipeline for BlueLight.* 