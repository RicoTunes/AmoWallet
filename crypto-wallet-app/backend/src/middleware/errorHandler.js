module.exports = (err, req, res, next) => {
  console.error('Error:', err?.message);
  let statusCode = 500;
  let message = 'Internal Server Error';
  
  if (err.name === 'ValidationError') {
    statusCode = 400;
    message = 'Validation Error';
  } else if (err.code === 'ECONNREFUSED') {
    statusCode = 503;
    message = 'Service Unavailable';
  }

  res.status(statusCode).json({
    success: false,
    error: message
  });
};
