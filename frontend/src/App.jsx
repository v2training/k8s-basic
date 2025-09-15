import React, { useState, useEffect } from 'react';
import axios from 'axios';
import './App.css';

function App() {
  const [users, setUsers] = useState([]);
  const [newUser, setNewUser] = useState({ name: '', email: '' });
  const [loading, setLoading] = useState(true);
  
  // Updated to use relative /api path - Ingress will route it
  const API_BASE_URL = '/api';

  useEffect(() => {
    fetchUsers();
  }, []);

  const fetchUsers = async () => {
    try {
      setLoading(true);
      const response = await axios.get(`${API_BASE_URL}/users`);
      setUsers(response.data);
    } catch (error) {
      console.error('Error fetching users:', error);
    } finally {
      setLoading(false);
    }
  };

  const createUser = async (e) => {
    e.preventDefault();
    try {
      const response = await axios.post(`${API_BASE_URL}/users`, newUser);
      
      //if I want to debug the response
      //console.log('Response status:', response.status);
      //console.log('Response data:', response.data);
      //console.log('Response data type:', typeof response.data);

      if (response.status === 200 || response.status === 201) {
        if (response.data && response.data.id) {
          console.log('Adding user to state:', response.data);
          setUsers(prevUsers => [...prevUsers, response.data]);
          setNewUser({ name: '', email: '' });
          console.log('User added successfully');
        } else {
          console.error('User creation response did not contain an ID.', response.data);          
          await fetchUsers();
          setNewUser({ name: '', email: '' });
        }
      }
    } catch (error) {
      console.error('Error creating user:', error);      
    }
  };

  return (
    <div className="App">
      <header className="App-header">
        <h1>Microservice Demo</h1>
        
        <form onSubmit={createUser} className="user-form">
          <h2>Add New User</h2>
          <input
            type="text"
            placeholder="Name"
            value={newUser.name}
            onChange={(e) => setNewUser({...newUser, name: e.target.value})}
            required
          />
          <input
            type="email"
            placeholder="Email"
            value={newUser.email}
            onChange={(e) => setNewUser({...newUser, email: e.target.value})}
            required
          />
          <button type="submit">Add User</button>
        </form>

        <div className="users-section">
          <h2>Users</h2>
          {loading ? (
            <p>Loading...</p>
          ) : (
            <div className="users-grid">
              {users.map(user => (
                <div key={user.id} className="user-card">
                  <h3>{user.name}</h3>
                  <p>{user.email}</p>
                </div>
              ))}
            </div>
          )}
        </div>
      </header>
    </div>
  );
}

export default App;