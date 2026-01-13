const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const crypto = require('crypto');

// DDoS Protection - Rate limiting
const ddosLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000, // Limit each IP to 1000 requests per windowMs
  message: {
    error: 'Too many requests from this IP, please try again later.',
    retryAfter: 15 * 60
  },
  standardHeaders: true,
  legacyHeaders: false,
});

// Stricter rate limit for sensitive endpoints
const strictLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 50,
  message: {
    error: 'Too many requests to this endpoint, please try again later.',
    retryAfter: 15 * 60
  },
  standardHeaders: true,
  legacyHeaders: false,
});

// Admin IP whitelist middleware
const adminIpWhitelist = (req, res, next) => {
  const allowedIps = process.env.ADMIN_WHITELIST_IPS 
    ? process.env.ADMIN_WHITELIST_IPS.split(',').map(ip => ip.trim())
    : ['127.0.0.1', '::1', 'localhost'];
  
  const clientIp = req.ip || req.connection.remoteAddress || req.socket.remoteAddress;
  const normalizedIp = clientIp?.replace('::ffff:', '') || '';
  
  // In development, allow all
  if (process.env.NODE_ENV === 'development') {
    return next();
  }
  
  if (allowedIps.includes(normalizedIp) || allowedIps.includes(clientIp)) {
    return next();
  }
  
  console.warn(`Blocked admin access attempt from IP: ${clientIp}`);
  return res.status(403).json({ error: 'Access denied' });
};

// Signature validation for sensitive operations
const validateSignature = (req, res, next) => {
  const signature = req.headers['x-signature'];
  const timestamp = req.headers['x-timestamp'];
  const apiSecret = process.env.API_SECRET || req.headers['x-api-secret'];
  
  // Skip signature validation in development
  if (process.env.NODE_ENV === 'development') {
    return next();
  }
  
  if (!signature || !timestamp) {
    return res.status(401).json({ error: 'Missing signature or timestamp' });
  }
  
  // Check timestamp is within 5 minutes
  const requestTime = parseInt(timestamp, 10);
  const currentTime = Date.now();
  if (Math.abs(currentTime - requestTime) > 5 * 60 * 1000) {
    return res.status(401).json({ error: 'Request timestamp expired' });
  }
  
  // Validate signature
  const payload = `${timestamp}${req.method}${req.originalUrl}${JSON.stringify(req.body || {})}`;
  const expectedSignature = crypto
    .createHmac('sha256', apiSecret)
    .update(payload)
    .digest('hex');
  
  if (signature !== expectedSignature) {
    return res.status(401).json({ error: 'Invalid signature' });
  }
  
  next();
};

// Apply comprehensive security middleware
const applySecurity = (app) => {
  // Helmet for security headers
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        scriptSrc: ["'self'"],
        imgSrc: ["'self'", "data:", "https:"],
        connectSrc: ["'self'", "https://api.coingecko.com", "https://api.1inch.io", "https://api.0x.org"],
      },
    },
    crossOriginEmbedderPolicy: false,
  }));
  
  // DDoS protection
  app.use(ddosLimiter);
  
  // Trust proxy (for correct IP detection behind reverse proxy)
  app.set('trust proxy', 1);
  
  console.log('✅ Security middleware applied (Helmet, DDoS protection)');
};

module.exports = {
  applySecurity,
  adminIpWhitelist,
  validateSignature,
  ddosLimiter,
  strictLimiter,
};
