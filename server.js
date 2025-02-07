require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const socketio = require('socket.io');
const http = require('http');
const cors = require('cors');
const morgan = require('morgan');
const cron = require('node-cron');
const auth = require('./middleware/auth');
const Pet = require('./models/Pet');
const CombatEngine = require('./services/combat');

const app = express();
const server = http.createServer(app);
const io = socketio(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Database Connection
mongoose.connect(process.env.MONGODB_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true
})
.then(() => console.log('MongoDB connected'))
.catch(err => console.error(err));

// Middleware
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

// Routes
app.use('/api/auth', require('./routes/auth'));
app.use('/api/pets', auth, require('./routes/pets'));

// WebSocket Combat System
io.on('connection', (socket) => {
  console.log('New client connected');
  
  socket.on('join-combat', async ({ petId, opponentId }) => {
    try {
      const [pet, opponent] = await Promise.all([
        Pet.findById(petId),
        Pet.findById(opponentId)
      ]);
      
      const combatEngine = new CombatEngine(pet, opponent);
      
      socket.on('combat-action', async (action) => {
        const result = await combatEngine.executeTurn(action);
        io.emit('combat-update', result);
        
        if (result.victor) {
          io.emit('combat-end', result);
          socket.removeAllListeners('combat-action');
        }
      });
      
      socket.on('disconnect', () => {
        console.log('Client disconnected');
        combatEngine.cleanup();
      });
    } catch (err) {
      socket.emit('combat-error', err.message);
    }
  });
});

// Stat Decay System
cron.schedule('0 * * * *', async () => { // Every hour
  try {
    await Pet.updateMany(
      { 
        'stats.hunger': { $gt: 0 }, 
        'stats.happiness': { $gt: 0 } 
      },
      { 
        $inc: { 
          'stats.hunger': -5,
          'stats.happiness': -3 
        } 
      }
    );
    console.log('Stats decay applied');
  } catch (err) {
    console.error('Stat decay error:', err);
  }
});

// Error Handling
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Server error' });
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
