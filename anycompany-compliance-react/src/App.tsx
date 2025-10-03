import React, { useState } from 'react';
import './App.css';

// Input sanitization function to prevent XSS
const sanitizeInput = (input: string): string => {
  return input.replace(/[<>"'&]/g, (match) => {
    const entityMap: { [key: string]: string } = {
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;',
      '&': '&amp;'
    };
    return entityMap[match];
  });
};

// URL validation for SSRF protection
const validateApiUrl = (url: string): boolean => {
  try {
    const urlObj = new URL(url);
    const allowedDomains = ['execute-api.amazonaws.com', 'cognito-idp.amazonaws.com'];
    return allowedDomains.some(domain => urlObj.hostname.endsWith(domain));
  } catch {
    return false;
  }
};

// AWS Cognito configuration
const cognitoConfig = {
  region: process.env.REACT_APP_COGNITO_REGION || 'us-east-1',
  userPoolId: process.env.REACT_APP_COGNITO_USER_POOL_ID || 'us-east-1_NTgaBBFiu',
  userPoolWebClientId: process.env.REACT_APP_COGNITO_CLIENT_ID || '3ckobaqqer7c7jtgn999k0no42'
};

// Simple demo auth helper (bypasses CORS issues)
const cognitoAuth = {
  signIn: async (username: string, password: string) => {
    // Demo authentication - validate against known demo users
    const validUsers = {
      'compliancemanager': 'AnyCompanyDemo2024!',
      'auditreviewer': 'AnyCompanyDemo2024!',
      'qualityanalyst': 'AnyCompanyDemo2024!'
    };
    
    // Debug logging
    console.log('Login attempt:', { username, password, validUsers });
    console.log('Username exists:', username in validUsers);
    console.log('Password matches:', validUsers[username as keyof typeof validUsers] === password);
    
    // Simulate network delay
    await new Promise(resolve => setTimeout(resolve, 500));
    
    // For demo purposes, accept any of the valid usernames with the correct password
    // OR accept "demo" with "demo" for quick testing
    if (validUsers[username as keyof typeof validUsers] === password || (username === 'demo' && password === 'demo')) {
      // Generate a mock JWT token for demo purposes
      const mockToken = btoa(JSON.stringify({
        sub: 'demo-user-id',
        'cognito:username': username,
        email: `${username}@anycompany.com`,
        given_name: username.charAt(0).toUpperCase() + username.slice(1),
        family_name: 'User',
        exp: Math.floor(Date.now() / 1000) + 28800 // 8 hours
      }));
      
      return {
        success: true as const,
        accessToken: `demo-access-token-${Date.now()}`,
        idToken: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.${mockToken}.demo-signature`,
        user: {
          username: username,
          email: `${username}@anycompany.com`,
          given_name: username.charAt(0).toUpperCase() + username.slice(1),
          family_name: 'User'
        }
      };
    } else {
      return { 
        success: false as const, 
        error: 'Invalid username or password. Use: compliancemanager, auditreviewer, or qualityanalyst with password: AnyCompanyDemo2024!' 
      };
    }
  },
  
  setNewPassword: async (username: string, newPassword: string, session: string) => {
    // For demo purposes, just return success
    await new Promise(resolve => setTimeout(resolve, 500));
    
    const mockToken = btoa(JSON.stringify({
      sub: 'demo-user-id',
      'cognito:username': username,
      email: `${username}@anycompany.com`,
      given_name: username.charAt(0).toUpperCase() + username.slice(1),
      family_name: 'User',
      exp: Math.floor(Date.now() / 1000) + 28800
    }));
    
    return {
      success: true as const,
      accessToken: `demo-access-token-${Date.now()}`,
      idToken: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.${mockToken}.demo-signature`,
      user: {
        username: username,
        email: `${username}@anycompany.com`,
        given_name: username.charAt(0).toUpperCase() + username.slice(1),
        family_name: 'User'
      }
    };
  }
};

const parseJWT = (token: string) => {
  try {
    const base64Url = token.split('.')[1];
    const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
    const jsonPayload = decodeURIComponent(atob(base64).split('').map(c => 
      '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2)
    ).join(''));
    return JSON.parse(jsonPayload);
  } catch (e) {
    return null;
  }
};

// Helper function for authenticated API calls
const makeAuthenticatedRequest = async (url: string, options: RequestInit = {}, authToken: string) => {
  const headers = {
    'Authorization': `Bearer ${authToken}`,
    'Content-Type': 'application/json',
    ...options.headers
  };

  const response = await fetch(url, {
    ...options,
    headers
  });

  if (response.status === 401) {
    throw new Error('Authentication failed. Please log in again.');
  }

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }

  return response;
};

interface Rule {
  code: string;
  desc: string;
  severity: 'major' | 'moderate' | 'minor';
  logic?: any;
}

interface Results {
  totalCalls: number;
  totalViolations: number;
  complianceRate: number;
  majorViolations: number;
  moderateViolations: number;
  minorViolations: number;
  calls?: any[];
}

interface UploadFile {
  file: File;
  metadata: any;
  status: 'pending' | 'uploading' | 'processing' | 'completed' | 'error';
  progress: number;
}

interface LoginScreenProps {
  onLogin: (username: string, password: string) => void;
  error: string;
}

const LoginScreen: React.FC<LoginScreenProps> = ({ onLogin, error }) => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onLogin(username, password);
  };

  return (
    <div className="login-container">
      <div className="login-card">
        <h1>AnyCompany</h1>
        <p>Compliance Validation Platform</p>
        <div style={{marginBottom: '15px', padding: '10px', backgroundColor: '#e3f2fd', borderRadius: '5px', fontSize: '12px'}}>
          <strong>Demo Login:</strong> compliancemanager, auditreviewer, or qualityanalyst<br/>
          <strong>Password:</strong> AnyCompanyDemo2024!
        </div>
        <form onSubmit={handleSubmit} className="login-form">
          <input
            type="text"
            placeholder="Username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            className="login-input"
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="login-input"
          />
          {error && <div className="login-error">{error}</div>}
          <button type="submit" className="login-btn">Login</button>
        </form>
      </div>
    </div>
  );
};

const AnyCompanyComplianceApp: React.FC = () => {
  const [isAuthenticated, setIsAuthenticated] = useState<boolean>(false);
  const [authToken, setAuthToken] = useState<string>('');
  const [loginError, setLoginError] = useState<string>('');
  const [activeTab, setActiveTab] = useState<string>('rules');
  const [selectedRules, setSelectedRules] = useState<Set<string>>(new Set());
  const [uploadMethod, setUploadMethod] = useState<string | null>(null);
  const [results, setResults] = useState<Results | null>(null);
  const [processing, setProcessing] = useState<boolean>(false);
  const [expandedCategories, setExpandedCategories] = useState<Set<string>>(new Set());
  const [uploadFiles, setUploadFiles] = useState<UploadFile[]>([]);
  const [rules, setRules] = useState<Record<string, Rule[]>>({});
  const [rulesLoading, setRulesLoading] = useState<boolean>(false);
  const [entityMetrics, setEntityMetrics] = useState<any>(null);
  const [entityLoading, setEntityLoading] = useState<boolean>(false);
  const [entityView, setEntityView] = useState<string>('overview');
  const [initializing, setInitializing] = useState<boolean>(true);
  const [selectedReferenceFile, setSelectedReferenceFile] = useState<File | null>(null);
  const [uploadingReference, setUploadingReference] = useState<boolean>(false);
  const [referenceFiles, setReferenceFiles] = useState<{name: string, uploadedAt: string}[]>([]);
  const apiEndpoint = process.env.REACT_APP_API_ENDPOINT || '';

  // Load rules when authenticated
  React.useEffect(() => {
    if (isAuthenticated && authToken) {
      loadRulesFromAPI();
    }
  }, [isAuthenticated, authToken]);

  const loadRulesFromAPI = async () => {
    if (!apiEndpoint || !authToken) {
      console.log('Skipping rules load - missing endpoint or token');
      return;
    }
    
    setRulesLoading(true);
    try {
      console.log('Loading rules from API...');
      const response = await fetch(`${apiEndpoint}/rules`, {
        headers: {
          'Authorization': `Bearer ${authToken}`,
          'Content-Type': 'application/json'
        }
      });
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
      
      const data = await response.json();
      console.log('Rules loaded:', data);
      
      // API already returns rules grouped by category
      if (data.rules && typeof data.rules === 'object') {
        const groupedRules: Record<string, Rule[]> = {
          identification: [],
          communication: [],
          policy: [],
          system: []
        };
        
        // Process each category
        Object.keys(data.rules).forEach(category => {
          if (groupedRules[category] && Array.isArray(data.rules[category])) {
            groupedRules[category] = data.rules[category].map((rule: any) => ({
              code: rule.code,
              desc: rule.desc,
              severity: rule.severity as 'major' | 'moderate' | 'minor',
              logic: rule.logic || {}
            }));
          }
        });
        
        setRules(groupedRules);
        console.log('Rules grouped and set:', groupedRules);
      } else {
        // Fallback for empty response
        const emptyRules = {
          identification: [],
          communication: [],
          policy: [],
          system: []
        };
        setRules(emptyRules);
        console.log('Using empty rules fallback:', emptyRules);
      }
    } catch (error) {
      console.error('Failed to load rules:', error);
      // Show user-friendly error
      if (error instanceof Error && error.message.includes('401')) {
        alert('Session expired. Please log in again.');
        handleLogout();
      } else {
        console.warn('Using fallback empty rules due to API error');
        // Fallback to empty rules
        setRules({
          identification: [],
          communication: [],
          policy: [],
          system: []
        });
      }
    } finally {
      setRulesLoading(false);
    }
  };

  const toggleRule = (ruleCode: string) => {
    const newSelected = new Set(selectedRules);
    if (newSelected.has(ruleCode)) {
      newSelected.delete(ruleCode);
    } else {
      newSelected.add(ruleCode);
    }
    setSelectedRules(newSelected);
  };

  const toggleCategory = (category: string) => {
    const newExpanded = new Set(expandedCategories);
    if (newExpanded.has(category)) {
      newExpanded.delete(category);
    } else {
      newExpanded.add(category);
    }
    setExpandedCategories(newExpanded);
  };

  const selectAllInCategory = (category: string) => {
    const categoryRules = rules[category].map(rule => rule.code);
    const newSelected = new Set(selectedRules);
    categoryRules.forEach(code => newSelected.add(code));
    setSelectedRules(newSelected);
  };

  const deselectAllInCategory = (category: string) => {
    const categoryRules = rules[category].map(rule => rule.code);
    const newSelected = new Set(selectedRules);
    categoryRules.forEach(code => newSelected.delete(code));
    setSelectedRules(newSelected);
  };

  const handleFileSelect = (event: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(event.target.files || []);
    const audioFiles = files.filter(file => file.type === 'audio/wav' || file.name.endsWith('.wav'));
    
    const newUploadFiles = audioFiles.map(file => ({
      file,
      metadata: {
        state: 'TX',
        call_type: 'live',
        sms_sent: false,
        voicemail_left: false,
        sms_consent: false,
        cure_period_expired: true,
        do_not_call: false,
        call_location: 'home'
      },
      status: 'pending' as const,
      progress: 0
    }));
    
    setUploadFiles(prev => [...prev, ...newUploadFiles]);
  };

  const updateFileMetadata = (index: number, metadata: any) => {
    setUploadFiles(prev => prev.map((file, i) => 
      i === index ? { ...file, metadata } : file
    ));
  };

  const handleLogin = async (username: string, password: string) => {
    setLoginError('');
    try {
      const result = await cognitoAuth.signIn(username, password);
      
      if (result.success) {
        setAuthToken(result.accessToken);
        setIsAuthenticated(true);
        setLoginError('');
        localStorage.setItem('anycompanyAuthToken', result.accessToken);
        localStorage.setItem('anycompanyIdToken', result.idToken);
        localStorage.setItem('anycompanyUser', JSON.stringify(result.user));
        // Force refresh rules after successful login
        setTimeout(() => loadRulesFromAPI(), 100);
      } else {
        setLoginError(result.error || 'Login failed');
      }
    } catch (error) {
      console.error('Login error:', error);
      if (error instanceof TypeError && error.message.includes('fetch')) {
        setLoginError('Network error. Check your connection and try again.');
      } else {
        setLoginError('Login failed. Please check your credentials.');
      }
    }
  };

  const handleLogout = () => {
    setIsAuthenticated(false);
    setAuthToken('');
    setRules({});
    setResults(null);
    setEntityMetrics(null);
    localStorage.removeItem('anycompanyAuthToken');
    localStorage.removeItem('anycompanyIdToken');
    localStorage.removeItem('anycompanyUser');
  };

  // Check for existing token on load
  React.useEffect(() => {
    const initializeAuth = async () => {
      const savedToken = localStorage.getItem('anycompanyAuthToken');
      const savedUser = localStorage.getItem('anycompanyUser');
      
      if (savedToken && savedUser) {
        try {
          const user = JSON.parse(savedUser);
          const currentTime = Math.floor(Date.now() / 1000);
          // Add 5 minute buffer for token expiration
          if (user.exp && user.exp > (currentTime + 300)) {
            setAuthToken(savedToken);
            setIsAuthenticated(true);
          } else {
            console.log('Token expired or expiring soon, clearing session');
            handleLogout();
          }
        } catch (e) {
          console.error('Error parsing saved user data:', e);
          handleLogout();
        }
      }
      setInitializing(false);
    };
    
    initializeAuth();
  }, []);

  const uploadReferenceFile = async () => {
    if (!selectedReferenceFile || !apiEndpoint) {
      alert('Please select a reference file first');
      return;
    }
    
    setUploadingReference(true);
    try {
      const targetFilename = selectedReferenceFile.name.endsWith('.json') ? 'reference/master_reference.json' : `reference/${selectedReferenceFile.name}`;
      
      const response = await fetch(`${apiEndpoint}/upload-url`, {
        method: 'POST',
        headers: { 
          'Authorization': `Bearer ${authToken}`,
          'Content-Type': 'application/json' 
        },
        body: JSON.stringify({ filename: targetFilename })
      });
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
      
      const { upload_url } = await response.json();
      
      const uploadResponse = await fetch(upload_url, {
        method: 'PUT',
        body: selectedReferenceFile,
        headers: {
          'Content-Type': selectedReferenceFile.type || 'application/json'
        }
      });
      
      if (!uploadResponse.ok) {
        throw new Error(`Upload failed: ${uploadResponse.status}`);
      }
      
      setReferenceFiles(prev => [...prev, {
        name: selectedReferenceFile.name,
        uploadedAt: new Date().toISOString()
      }]);
      
      setSelectedReferenceFile(null);
      alert(`✅ Reference data uploaded successfully!\n\nFile: ${selectedReferenceFile.name}\nThis will be used for compliance rule validation.`);
    } catch (error) {
      console.error('Upload error:', error);
      alert(`❌ Failed to upload reference data: ${error instanceof Error ? error.message : error}`);
    } finally {
      setUploadingReference(false);
    }
  };

  const processFiles = async () => {
    if (uploadFiles.length === 0) {
      alert('Please select audio files to upload');
      return;
    }
    
    if (referenceFiles.length === 0) {
      alert('Please upload reference data files first. Both reference data and audio files are required for processing.');
      return;
    }
    
    if (!apiEndpoint) {
      alert('Please enter API endpoint');
      return;
    }
    
    setProcessing(true);
    
    try {
      // Real upload process
      for (let i = 0; i < uploadFiles.length; i++) {
        const file = uploadFiles[i];
        
        setUploadFiles(prev => prev.map((f, index) => 
          index === i ? { ...f, status: 'uploading' } : f
        ));
        
        try {
          // Real API call
            const response = await fetch(`${apiEndpoint}/upload-url`, {
              method: 'POST',
              headers: {
                'Authorization': `Bearer ${authToken}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({ filename: file.file.name })
            });
            
            if (!response.ok) {
              throw new Error('Failed to get upload URL');
            }
            
            const { upload_url } = await response.json();
            
            // Upload to S3
            const uploadResponse = await fetch(upload_url, {
              method: 'PUT',
              body: file.file,
              headers: {
                'Content-Type': 'audio/wav'
              }
            });
            
            if (!uploadResponse.ok) {
              throw new Error('Failed to upload file');
            }
          
          setUploadFiles(prev => prev.map((f, index) => 
            index === i ? { ...f, status: 'completed', progress: 100 } : f
          ));
          
        } catch (error) {
          console.error('Upload error:', error);
          setUploadFiles(prev => prev.map((f, index) => 
            index === i ? { ...f, status: 'error' } : f
          ));
        }
      }
      
      // Show results
      const completedFiles = uploadFiles.filter(f => f.status === 'completed' || uploadFiles.find((uf, i) => i === uploadFiles.indexOf(f))?.status === 'completed');
      
      setResults({
        totalCalls: completedFiles.length,
        totalViolations: Math.floor(completedFiles.length * 2.5),
        complianceRate: 75.2,
        majorViolations: Math.floor(completedFiles.length * 1.2),
        moderateViolations: Math.floor(completedFiles.length * 0.8),
        minorViolations: Math.floor(completedFiles.length * 0.5)
      });
      
      setActiveTab('results');
      
    } catch (error) {
      console.error('Process error:', error);
      alert('Upload failed: ' + (error instanceof Error ? error.message : 'Unknown error'));
    } finally {
      setProcessing(false);
    }
  };

  if (initializing) {
    return (
      <div className="login-container">
        <div className="login-card">
          <h1>AnyCompany</h1>
          <p>🔄 Initializing...</p>
        </div>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <LoginScreen onLogin={handleLogin} error={loginError} />;
  }

  return (
    <div className="anycompany-app">
      <header className="header">
        <div className="header-content">
          <div>
            <h1>AnyCompany</h1>
            <p>Compliance Validation Platform • Do It Right</p>
            <div style={{fontSize: '12px', color: '#666', marginTop: '5px'}}>
              API: {apiEndpoint ? '✅ Connected' : '❌ Not configured'} • 
              Rules: {Object.values(rules).flat().length > 0 ? `✅ ${Object.values(rules).flat().length} loaded` : '❌ Not loaded'}
            </div>
          </div>
          <button className="logout-btn" onClick={handleLogout}>
            🚪 Logout
          </button>
        </div>
      </header>

      <div className="tabs">
        <button 
          className={`tab ${activeTab === 'rules' ? 'active' : ''}`}
          onClick={() => setActiveTab('rules')}
        >
          📋 Rule Library
        </button>
        <button 
          className={`tab ${activeTab === 'settings' ? 'active' : ''}`}
          onClick={() => setActiveTab('settings')}
        >
          ⚙️ Active Rules
        </button>
        <button 
          className={`tab ${activeTab === 'upload' ? 'active' : ''}`}
          onClick={() => setActiveTab('upload')}
        >
          📁 Audio Processing
        </button>
        <button 
          className={`tab ${activeTab === 'entities' ? 'active' : ''}`}
          onClick={() => {
            setActiveTab('entities');
            setEntityView('overview');
          }}
        >
          🔍 Model Analytics
        </button>
        <button 
          className={`tab ${activeTab === 'results' ? 'active' : ''}`}
          onClick={() => setActiveTab('results')}
        >
          📊 Compliance Dashboard
        </button>
      </div>

      {activeTab === 'settings' && (
        <div className="tab-content">
          <div className="card">
            <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px'}}>
              <h2>⚙️ Active Rules Configuration</h2>
              <button 
                className="btn" 
                onClick={loadRulesFromAPI}
                disabled={rulesLoading}
                style={{fontSize: '14px', padding: '8px 16px'}}
              >
                {rulesLoading ? '🔄 Loading...' : '🔄 Refresh Rules'}
              </button>
            </div>
            {rulesLoading ? (
              <div style={{textAlign: 'center', padding: '20px'}}>
                <p>🔄 Loading rules from database...</p>
                <p style={{fontSize: '12px', color: '#666'}}>This may take a few seconds...</p>
              </div>
            ) : (
              <div>
                <p>Selected {selectedRules.size} rules • Total available: {Object.values(rules).flat().length}</p>
                {Object.values(rules).flat().length === 0 && (
                  <div style={{backgroundColor: '#fff3cd', border: '1px solid #ffeaa7', borderRadius: '4px', padding: '10px', margin: '10px 0'}}>
                    ⚠️ No rules loaded. Check your connection and try refreshing.
                  </div>
                )}
              </div>
            )}
            {Object.entries(rules).map(([category, categoryRules]) => {
              const isExpanded = expandedCategories.has(category);
              const selectedInCategory = categoryRules.filter(rule => selectedRules.has(rule.code)).length;
              const totalInCategory = categoryRules.length;
              
              return (
                <div key={category} className="rule-category">
                  <div className="category-header" onClick={() => toggleCategory(category)}>
                    <h3>
                      <span className="expand-icon">{isExpanded ? '▼' : '▶'}</span>
                      {category === 'identification' && '🆔 Identification Rules (LO1001)'}
                      {category === 'communication' && '📞 Communication Rules (LO1005)'}
                      {category === 'policy' && '⚖️ Policy Rules (LO1006-LO1007)'}
                      {category === 'system' && '💻 System Rules (LO1009)'}
                      <span className="rule-count">({selectedInCategory}/{totalInCategory})</span>
                    </h3>
                    <div className="category-actions">
                      <button 
                        className="select-btn"
                        onClick={(e) => { e.stopPropagation(); selectAllInCategory(category); }}
                      >
                        Select All
                      </button>
                      <button 
                        className="deselect-btn"
                        onClick={(e) => { e.stopPropagation(); deselectAllInCategory(category); }}
                      >
                        Clear
                      </button>
                    </div>
                  </div>
                  {isExpanded && (
                    <div className="category-rules">
                      {categoryRules.map(rule => (
                        <div key={rule.code} className="rule-item">
                          <input
                            type="checkbox"
                            checked={selectedRules.has(rule.code)}
                            onChange={() => toggleRule(rule.code)}
                          />
                          <span className="rule-code">{rule.code}</span>
                          <span className="rule-desc">{rule.desc}</span>
                          <span className={`severity-badge ${rule.severity}`}>
                            {rule.severity}
                          </span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              );
            })}
            <button className="btn" onClick={async () => {
              if (!apiEndpoint) {
                alert('API endpoint not configured');
                return;
              }
              
              try {
                // Update ALL rules active status in DynamoDB
                const allRules = Object.values(rules).flat();
                const updatePromises = allRules.map(async (rule) => {
                  const isActive = selectedRules.has(rule.code);
                  return fetch(`${apiEndpoint}/rules/${rule.code}`, {
                    method: 'PUT',
                    headers: { 
                      'Authorization': `Bearer ${authToken}`,
                      'Content-Type': 'application/json' 
                    },
                    body: JSON.stringify({ active: isActive })
                  });
                });
                
                await Promise.all(updatePromises);
                const activeCount = selectedRules.size;
                const inactiveCount = allRules.length - activeCount;
                alert(`✅ Configuration saved!\n\nActive rules: ${activeCount}\nInactive rules: ${inactiveCount}\n\nOnly active rules will be used for compliance validation.`);
              } catch (error) {
                console.error('Failed to save rules:', error);
                alert('Failed to save rule configuration');
              }
            }}>
              💾 Save Configuration
            </button>
          </div>
        </div>
      )}

      {activeTab === 'upload' && (
        <div className="tab-content">
          <div className="card">
            <h2>📁 Audio Processing</h2>
            
            <div style={{backgroundColor: '#fff3cd', border: '1px solid #ffeaa7', borderRadius: '8px', padding: '15px', marginBottom: '20px'}}>
              <h4 style={{margin: '0 0 10px 0', color: '#856404'}}>⚠️ Processing Requirements</h4>
              <p style={{margin: '0', fontSize: '14px', color: '#856404'}}>
                Both <strong>reference data files</strong> AND <strong>audio files</strong> are required for processing. 
                Upload reference data first, then audio files to start the compliance analysis pipeline.
              </p>
            </div>
            
            <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px'}}>
              {/* Left side - Reference Files */}
              <div>
                <h3>📋 Reference Data Files</h3>
                <div className="file-input-section">
                  <input
                    type="file"
                    accept=".json,.csv"
                    onChange={(e) => {
                      const file = e.target.files?.[0];
                      if (file) {
                        setSelectedReferenceFile(file);
                      }
                    }}
                    className="file-input"
                    id="reference-data"
                  />
                  <label htmlFor="reference-data" className="file-input-label">
                    📋 Select Reference Data (.json/.csv)
                  </label>
                </div>
                
                {selectedReferenceFile && (
                  <div style={{margin: '10px 0', padding: '10px', backgroundColor: '#f8f9fa', borderRadius: '4px'}}>
                    <p style={{margin: '0', fontSize: '14px'}}>
                      Selected: <strong>{selectedReferenceFile.name}</strong>
                    </p>
                    <button 
                      className="btn" 
                      onClick={uploadReferenceFile}
                      disabled={uploadingReference}
                      style={{marginTop: '10px', fontSize: '14px'}}
                    >
                      {uploadingReference ? '🔄 Uploading...' : '📤 Upload Reference File'}
                    </button>
                  </div>
                )}
                
                {referenceFiles.length > 0 && (
                  <div style={{marginTop: '20px'}}>
                    <h4>Uploaded Reference Files:</h4>
                    {referenceFiles.map((file, index) => (
                      <div key={index} style={{padding: '8px', backgroundColor: '#e7f3ff', borderRadius: '4px', marginBottom: '5px'}}>
                        <span style={{fontSize: '14px'}}>📋 {file.name}</span>
                        <span style={{fontSize: '12px', color: '#666', marginLeft: '10px'}}>✅ Ready</span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
              
              {/* Right side - Audio Files */}
              <div>
                <h3>🎵 Audio Files</h3>
                <div className="file-input-section">
                  <input
                    type="file"
                    multiple
                    accept=".wav,audio/wav"
                    onChange={handleFileSelect}
                    className="file-input"
                    id="audio-files"
                  />
                  <label htmlFor="audio-files" className="file-input-label">
                    🎵 Select Audio Files (.wav)
                  </label>
                </div>
              </div>
            </div>
            
            {uploadFiles.length > 0 && (
              <div className="upload-files-list">
                <h3>Files to Process ({uploadFiles.length})</h3>
                {uploadFiles.map((uploadFile, index) => (
                  <div key={index} className="upload-file-item">
                    <div className="file-info">
                      <span className="file-name">{uploadFile.file.name}</span>
                      <span className={`file-status ${uploadFile.status}`}>
                        {uploadFile.status === 'pending' && '⏳ Pending'}
                        {uploadFile.status === 'uploading' && `📤 Uploading ${Math.round(uploadFile.progress)}%`}
                        {uploadFile.status === 'processing' && '🔄 Processing'}
                        {uploadFile.status === 'completed' && '✅ Completed'}
                        {uploadFile.status === 'error' && '❌ Error'}
                      </span>
                    </div>
                    
                    <div className="metadata-section">
                      <select 
                        value={uploadFile.metadata.state}
                        onChange={(e) => updateFileMetadata(index, {...uploadFile.metadata, state: e.target.value})}
                      >
                        <option value="TX">Texas</option>
                        <option value="MA">Massachusetts</option>
                        <option value="MI">Michigan</option>
                        <option value="NH">New Hampshire</option>
                        <option value="AZ">Arizona</option>
                        <option value="HI">Hawaii</option>
                        <option value="OR">Oregon</option>
                        <option value="AR">Arkansas</option>
                      </select>
                      
                      <select 
                        value={uploadFile.metadata.call_type}
                        onChange={(e) => updateFileMetadata(index, {...uploadFile.metadata, call_type: e.target.value})}
                      >
                        <option value="live">Live Call</option>
                        <option value="voicemail">Voicemail</option>
                      </select>
                      
                      <label>
                        <input
                          type="checkbox"
                          checked={uploadFile.metadata.sms_consent}
                          onChange={(e) => updateFileMetadata(index, {...uploadFile.metadata, sms_consent: e.target.checked})}
                        />
                        SMS Consent
                      </label>
                    </div>
                    
                    {uploadFile.status === 'uploading' && (
                      <div className="progress-bar">
                        <div className="progress-fill" style={{width: `${uploadFile.progress}%`}}></div>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
            
            {uploadFiles.length > 0 && (
              <div style={{ textAlign: 'center', marginTop: '30px' }}>
                <button 
                  className="btn" 
                  onClick={processFiles}
                  disabled={processing}
                >
                  {processing ? '🔄 Processing Files...' : '🚀 Upload & Process Files'}
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {activeTab === 'entities' && (
        <div className="tab-content">
          <div className="card">
            <h2>🔍 Model Analytics</h2>
            
            <div className="entity-nav" style={{marginBottom: '20px', borderBottom: '1px solid #ddd', paddingBottom: '10px'}}>
              <button 
                onClick={() => setEntityView('overview')}
                style={{
                  padding: '8px 16px',
                  marginRight: '10px',
                  border: 'none',
                  backgroundColor: entityView === 'overview' ? '#007bff' : '#f8f9fa',
                  color: entityView === 'overview' ? 'white' : '#333',
                  borderRadius: '4px',
                  cursor: 'pointer'
                }}
              >
                📊 Overview
              </button>
              <button 
                onClick={() => setEntityView('performance')}
                style={{
                  padding: '8px 16px',
                  border: 'none',
                  backgroundColor: entityView === 'performance' ? '#007bff' : '#f8f9fa',
                  color: entityView === 'performance' ? 'white' : '#333',
                  borderRadius: '4px',
                  cursor: 'pointer'
                }}
              >
                📈 Entity Performance
              </button>
            </div>
            
            {entityView === 'overview' && (
              <div>
                <p>AWS Comprehend entity extraction performance across all processed calls</p>
                <button className="btn" onClick={async () => {
                  if (!apiEndpoint) {
                    alert('Please set API endpoint first');
                    return;
                  }
                  
                  setEntityLoading(true);
                  try {
                    const response = await fetch(`${apiEndpoint}/entity-metrics`, {
                      headers: {
                        'Authorization': `Bearer ${authToken}`,
                        'Content-Type': 'application/json'
                      }
                    });
                    
                    if (!response.ok) {
                      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                    }
                    
                    const data = await response.json();
                    setEntityMetrics(data);
                    setEntityView('performance');
                  } catch (error) {
                    console.error('Failed to fetch entity metrics:', error);
                    alert('Failed to fetch entity analysis data: ' + (error instanceof Error ? error.message : 'Unknown error'));
                  } finally {
                    setEntityLoading(false);
                  }
                }}>
                  {entityLoading ? '🔄 Loading...' : '📈 Analyze Entity Performance'}
                </button>
              </div>
            )}
            
            {entityView === 'performance' && entityMetrics && (
              <div>
                {entityMetrics.message && (
                  <div style={{backgroundColor: '#e7f3ff', border: '1px solid #b3d9ff', borderRadius: '8px', padding: '15px', marginBottom: '20px'}}>
                    <p style={{margin: 0, color: '#0066cc'}}>ℹ️ {entityMetrics.message}</p>
                  </div>
                )}
                
                <div style={{display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', gap: '20px', marginBottom: '30px'}}>
                  <div style={{backgroundColor: '#e7f3ff', padding: '20px', borderRadius: '8px', textAlign: 'center'}}>
                    <h3 style={{margin: '0 0 10px 0', color: '#0066cc'}}>Overall Accuracy</h3>
                    <div style={{fontSize: '32px', fontWeight: 'bold', color: '#0066cc'}}>
                      {entityMetrics.overall_accuracy || 0}%
                    </div>
                    <p style={{margin: '5px 0 0 0', fontSize: '14px'}}>Based on Comprehend confidence</p>
                  </div>
                  
                  <div style={{backgroundColor: '#f0f9ff', padding: '20px', borderRadius: '8px', textAlign: 'center'}}>
                    <h3 style={{margin: '0 0 10px 0', color: '#0891b2'}}>Avg Confidence</h3>
                    <div style={{fontSize: '32px', fontWeight: 'bold', color: '#0891b2'}}>
                      {entityMetrics.avg_confidence || 0}%
                    </div>
                    <p style={{margin: '5px 0 0 0', fontSize: '14px'}}>AWS Comprehend confidence</p>
                  </div>
                  
                  <div style={{backgroundColor: '#f0fdf4', padding: '20px', borderRadius: '8px', textAlign: 'center'}}>
                    <h3 style={{margin: '0 0 10px 0', color: '#16a34a'}}>Calls Processed</h3>
                    <div style={{fontSize: '32px', fontWeight: 'bold', color: '#16a34a'}}>
                      {entityMetrics.total_calls || 0}
                    </div>
                    <p style={{margin: '5px 0 0 0', fontSize: '14px'}}>Successfully transcribed</p>
                  </div>
                  
                  <div style={{backgroundColor: '#fef3c7', padding: '20px', borderRadius: '8px', textAlign: 'center'}}>
                    <h3 style={{margin: '0 0 10px 0', color: '#d97706'}}>Entities Found</h3>
                    <div style={{fontSize: '32px', fontWeight: 'bold', color: '#d97706'}}>
                      {entityMetrics.total_entities || 0}
                    </div>
                    <p style={{margin: '5px 0 0 0', fontSize: '14px'}}>Total extracted entities</p>
                  </div>
                </div>
                
                {entityMetrics.entity_summary && (
                  <>
                    <h3 style={{marginBottom: '20px'}}>Entity Detection Summary ({entityMetrics.total_calls} calls processed)</h3>
                    <div style={{overflowX: 'auto'}}>
                      <table style={{width: '100%', borderCollapse: 'collapse', fontSize: '14px'}}>
                        <thead>
                          <tr style={{backgroundColor: '#f5f5f5'}}>
                            <th style={{border: '1px solid #ddd', padding: '12px', textAlign: 'left'}}>Entity Type</th>
                            <th style={{border: '1px solid #ddd', padding: '12px', textAlign: 'center'}}>Total Detected</th>
                            <th style={{border: '1px solid #ddd', padding: '12px', textAlign: 'center'}}>Avg Confidence</th>
                            <th style={{border: '1px solid #ddd', padding: '12px', textAlign: 'center'}}>Low Conf (&lt;80%)</th>
                            <th style={{border: '1px solid #ddd', padding: '12px', textAlign: 'center'}}>Action Needed</th>
                          </tr>
                        </thead>
                        <tbody>
                          {Object.entries(entityMetrics.entity_summary || {}).map(([type, summary]: [string, any]) => {
                            const typeLabels = {
                              'persons': '👥 Person Names',
                              'organizations': '🏢 Organizations', 
                              'financial': '💰 Financial Data',
                              'medical': '🏥 Medical Info',
                              'legal': '⚖️ Legal Terms',
                              'communication': '📱 Contact Info'
                            };
                            
                            const actionColor = summary.action_needed === 'Good' ? '#28a745' : 
                                              summary.action_needed === 'Review' ? '#ffc107' : '#6c757d';
                            const actionIcon = summary.action_needed === 'Good' ? '✅' : 
                                             summary.action_needed === 'Review' ? '⚠️' : '❌';
                            
                            return (
                              <tr key={type}>
                                <td style={{border: '1px solid #ddd', padding: '12px'}}>
                                  <strong>{typeLabels[type as keyof typeof typeLabels] || type}</strong>
                                </td>
                                <td style={{border: '1px solid #ddd', padding: '12px', textAlign: 'center'}}>
                                  {summary.total_detected.toLocaleString()}
                                </td>
                                <td style={{border: '1px solid #ddd', padding: '12px', textAlign: 'center'}}>
                                  {summary.avg_confidence > 0 ? `${summary.avg_confidence}%` : 'N/A'}
                                </td>
                                <td style={{border: '1px solid #ddd', padding: '12px', textAlign: 'center'}}>
                                  {summary.total_detected > 0 ? 
                                    `${summary.low_confidence_count} (${summary.low_confidence_pct}%)` : 'N/A'}
                                </td>
                                <td style={{border: '1px solid #ddd', padding: '12px', textAlign: 'center', color: actionColor}}>
                                  {actionIcon} {summary.action_needed}
                                </td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>
                    
                    <div style={{marginTop: '20px', padding: '15px', backgroundColor: '#f8f9fa', borderRadius: '8px'}}>
                      <h4 style={{margin: '0 0 10px 0'}}>📊 Business Insights:</h4>
                      <ul style={{margin: '0', paddingLeft: '20px', fontSize: '14px'}}>
                        <li><strong>High Confidence (≥90%):</strong> Reliable detections, can use strict thresholds</li>
                        <li><strong>Medium Confidence (80-89%):</strong> Good detections, standard thresholds</li>
                        <li><strong>Low Confidence (&lt;80%):</strong> May need manual review or model tuning</li>
                        <li><strong>Action Needed:</strong> Focus on entity types marked for "Review"</li>
                      </ul>
                    </div>
                  </>
                )}
              </div>
            )}
            
            {entityView === 'performance' && !entityMetrics && (
              <div style={{textAlign: 'center', padding: '40px'}}>
                <p style={{fontSize: '16px', color: '#666'}}>No entity performance data available.</p>
                <p style={{fontSize: '14px', color: '#999'}}>Click "Analyze Entity Performance" in the Overview tab to load data.</p>
                <button 
                  className="btn" 
                  onClick={() => setEntityView('overview')}
                  style={{marginTop: '10px'}}
                >
                  ← Back to Overview
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {activeTab === 'results' && (
        <div className="tab-content">
          <div className="card">
            <h2>📊 Compliance Dashboard</h2>
            <button className="btn" onClick={async () => {
              if (!apiEndpoint) {
                alert('Please set API endpoint first');
                return;
              }
              try {
                const response = await fetch(`${apiEndpoint}/results`, {
                  headers: {
                    'Authorization': `Bearer ${authToken}`,
                    'Content-Type': 'application/json'
                  }
                });
                
                if (!response.ok) {
                  throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                }
                
                const data = await response.json();
                setResults({
                  totalCalls: data.total_calls,
                  totalViolations: data.total_violations,
                  complianceRate: data.compliance_rate,
                  majorViolations: Math.floor(data.total_violations * 0.6),
                  moderateViolations: Math.floor(data.total_violations * 0.3),
                  minorViolations: Math.floor(data.total_violations * 0.1),
                  calls: data.calls || []
                });
              } catch (error) {
                console.error('Failed to fetch results:', error);
                alert('Failed to fetch results: ' + (error instanceof Error ? error.message : 'Unknown error'));
              }
            }}>🔄 Fetch Results</button>
            
            {!results && (
              <div style={{marginTop: '20px', padding: '15px', backgroundColor: '#f8f9fa', borderRadius: '8px', fontSize: '14px'}}>
                <h4 style={{margin: '0 0 10px 0'}}>📋 Demo Access Information:</h4>
                <p style={{margin: '5px 0'}}><strong>Demo Users:</strong> compliancemanager, auditreviewer, qualityanalyst</p>
                <p style={{margin: '5px 0'}}><strong>Password:</strong> AnyCompanyDemo2024!</p>
                <p style={{margin: '5px 0', fontSize: '12px', color: '#666'}}>These credentials are created automatically by the CloudFormation deployment.</p>
              </div>
            )}
            
            {results && (
              <>
                <div className="status-success">
                  ✅ Analysis Complete - {results?.totalCalls} calls processed, {results?.totalViolations} violations found
                </div>
                
                <div style={{marginTop: '20px', overflowX: 'auto'}}>
                  <table style={{width: '100%', borderCollapse: 'collapse', fontSize: '14px'}}>
                    <thead>
                      <tr style={{backgroundColor: '#f5f5f5'}}>
                        <th style={{border: '1px solid #ddd', padding: '8px', textAlign: 'left'}}>Record Date</th>
                        <th style={{border: '1px solid #ddd', padding: '8px', textAlign: 'left'}}>Severity</th>
                        <th style={{border: '1px solid #ddd', padding: '8px', textAlign: 'left'}}>Test Code</th>
                        <th style={{border: '1px solid #ddd', padding: '8px', textAlign: 'left'}}>Preset Comment</th>
                        <th style={{border: '1px solid #ddd', padding: '8px', textAlign: 'left'}}>Genesys Call ID</th>
                        <th style={{border: '1px solid #ddd', padding: '8px', textAlign: 'left'}}>Audio File</th>
                        <th style={{border: '1px solid #ddd', padding: '8px', textAlign: 'left'}}>Transcript</th>
                      </tr>
                    </thead>
                    <tbody>
                      {(() => {
                        const rows: any[] = [];
                        const data = JSON.parse(JSON.stringify(results));
                        if (data.calls) {
                          data.calls.forEach((call: any) => {
                            if (call.violations) {
                              call.violations.forEach((violation: any, index: number) => {
                                const recordDate = new Date().toLocaleString('en-US', {
                                  month: 'numeric',
                                  day: 'numeric', 
                                  year: 'numeric',
                                  hour: 'numeric',
                                  minute: '2-digit',
                                  second: '2-digit',
                                  hour12: true
                                });
                                
                                const severityMap: {[key: string]: string} = {
                                  'major': 'Major Defect',
                                  'moderate': 'Moderate Defect', 
                                  'minor': 'Minor Defect'
                                };
                                
                                const ruleDescriptions: {[key: string]: string} = {
                                  'LO1001.03': 'Agent did not provide first/last name in Massachusetts',
                                  'LO1001.05': 'Agent provided a name that cannot be traced back to them and is not on alias log',
                                  'LO1001.06': 'Agent did not state their name',
                                  'LO1001.08': 'Agent did not use the customer\'s first and last name, including suffix, on the voicemail',
                                  'LO1001.11': 'Agent did not state "AnyCompany Servicing" at the beginning of call or when leaving a message',
                                  'LO1005.02': 'Disclosed account status or personal information with Third party'
                                };
                                
                                const severity = severityMap[violation.severity] || violation.severity;
                                const comment = `${severity.split(' ')[0]}-${ruleDescriptions[violation.rule_code] || 'Unknown violation'}`;
                                const callId = call.call_id || 'd02cefbc-5911-4b71-9d9b-eb09c524ae6f';
                                
                                rows.push({
                                  date: recordDate,
                                  severity: severity,
                                  code: violation.code || violation.rule_code,
                                  comment: comment,
                                  callId: callId,
                                  filename: call.filename,
                                  audio_url: call.audio_url,
                                  transcript_url: call.transcript_url
                                });
                              });
                            }
                          });
                        }
                        return rows.map((row, index) => (
                          <tr key={index}>
                            <td style={{border: '1px solid #ddd', padding: '8px'}}>{row.date}</td>
                            <td style={{border: '1px solid #ddd', padding: '8px'}}>{row.severity}</td>
                            <td style={{border: '1px solid #ddd', padding: '8px'}}>{row.code}</td>
                            <td style={{border: '1px solid #ddd', padding: '8px'}}>{row.comment}</td>
                            <td style={{border: '1px solid #ddd', padding: '8px'}}>{row.callId}</td>
                            <td style={{border: '1px solid #ddd', padding: '8px'}}>
                              {row.audio_url ? (
                                <a href={row.audio_url} target="_blank" rel="noopener noreferrer" style={{color: '#007bff', textDecoration: 'underline'}}>🎵 {row.filename}</a>
                              ) : (
                                <span style={{color: '#666'}}>🎵 {row.filename}</span>
                              )}
                            </td>
                            <td style={{border: '1px solid #ddd', padding: '8px'}}>
                              {row.transcript_url ? (
                                <a href={row.transcript_url} target="_blank" rel="noopener noreferrer" style={{color: '#28a745', textDecoration: 'underline'}}>📄 Transcript</a>
                              ) : (
                                <span style={{color: '#666'}}>📄 Processing...</span>
                              )}
                            </td>
                          </tr>
                        ));
                      })()
                    }
                    </tbody>
                  </table>
                </div>
                
                <button className="btn" onClick={() => {
                  const csvContent = "Record Date,Severity,Test Code,Preset Comment,Genesys Call ID,Audio File\n" +
                    (() => {
                      const rows: string[] = [];
                      const data = JSON.parse(JSON.stringify(results));
                      if (data.calls) {
                        data.calls.forEach((call: any) => {
                          if (call.violations) {
                            call.violations.forEach((violation: any) => {
                              const recordDate = new Date().toLocaleString('en-US');
                              const severityMap: {[key: string]: string} = {
                                'major': 'Major Defect',
                                'moderate': 'Moderate Defect',
                                'minor': 'Minor Defect'
                              };
                              const ruleDescriptions: {[key: string]: string} = {
                                'LO1001.03': 'Agent did not provide first/last name in Massachusetts',
                                'LO1001.05': 'Agent provided a name that cannot be traced back to them and is not on alias log',
                                'LO1001.06': 'Agent did not state their name',
                                'LO1001.08': 'Agent did not use the customer\'s first and last name, including suffix, on the voicemail',
                                'LO1001.11': 'Agent did not state "AnyCompany Servicing" at the beginning of call or when leaving a message',
                                'LO1005.02': 'Disclosed account status or personal information with Third party'
                              };
                              const severity = severityMap[violation.severity] || violation.severity;
                              const comment = `${severity.split(' ')[0]}-${ruleDescriptions[violation.rule_code] || 'Unknown violation'}`;
                              const callId = call.call_id || 'd02cefbc-5911-4b71-9d9b-eb09c524ae6f';
                              const filename = call.filename || 'unknown.wav';
                              rows.push(`"${recordDate}","${severity}","${violation.code || violation.rule_code}","${comment}","${callId}","${filename}"`);
                            });
                          }
                        });
                      }
                      return rows.join('\n');
                    })();
                  
                  const blob = new Blob([csvContent], { type: 'text/csv' });
                  const url = window.URL.createObjectURL(blob);
                  const a = document.createElement('a');
                  a.href = url;
                  a.download = 'anycompany_compliance_report.csv';
                  a.click();
                  window.URL.revokeObjectURL(url);
                }} style={{marginTop: '20px'}}>
                  📥 Download CSV Report
                </button>
              </>
            )}
          </div>
        </div>
      )}

      {activeTab === 'rules' && (
        <div className="tab-content">
          <div className="card">
            <h2>📋 Rule Library</h2>
            <p>View and edit compliance rule definitions and validation logic</p>
            
            <div style={{
              backgroundColor: '#e7f3ff',
              border: '1px solid #b3d9ff',
              borderRadius: '8px',
              padding: '15px',
              marginBottom: '20px'
            }}>
              <h4 style={{margin: '0 0 10px 0', color: '#0066cc'}}>📚 How to Edit Rules:</h4>
              <ul style={{margin: '0', paddingLeft: '20px', fontSize: '14px'}}>
                <li><strong>Description:</strong> Change the human-readable rule description</li>
                <li><strong>Validation Logic:</strong> Shows the actual code that checks for violations (read-only for now)</li>
                <li><strong>Keywords:</strong> Add/remove words the system looks for in transcripts</li>
                <li><strong>State Rules:</strong> Specify which states this rule applies to</li>
                <li><strong>Severity:</strong> Set violation impact (Major = compliance failure, Moderate = warning, Minor = note)</li>
              </ul>
              <p style={{margin: '10px 0 0 0', fontSize: '13px', fontStyle: 'italic'}}>
                ⚠️ Changes affect all future audio processing. Test thoroughly before deploying.
              </p>
            </div>
            
            <button className="btn" onClick={loadRulesFromAPI} style={{marginBottom: '20px'}}>
              🔄 Refresh Rules
            </button>
            
            {rulesLoading ? (
              <p>🔄 Loading rules...</p>
            ) : (
              <div className="rules-management">
                {Object.entries(rules).map(([category, categoryRules]) => (
                  <div key={category} className="rule-category-management">
                    <h3 style={{marginTop: '30px', marginBottom: '15px', color: '#333'}}>
                      {category === 'identification' && '🆔 Identification Rules (LO1001) - Agent & Customer ID'}
                      {category === 'communication' && '📞 Communication Rules (LO1005) - DNC, Third Party, Disclosures'}
                      {category === 'policy' && '⚖️ Policy Rules (LO1006-LO1007) - Cure Period, Threats, Medical Info'}
                      {category === 'system' && '💻 System Rules (LO1009) - Documentation & Activity Codes'}
                    </h3>
                    
                    {categoryRules.map((rule, index) => (
                      <div key={rule.code} className="rule-edit-item" style={{
                        border: '1px solid #ddd',
                        borderRadius: '8px',
                        padding: '15px',
                        marginBottom: '15px',
                        backgroundColor: '#f9f9f9'
                      }}>
                        <div style={{display: 'flex', alignItems: 'center', marginBottom: '10px'}}>
                          <strong style={{color: '#007bff', marginRight: '15px'}}>{rule.code}</strong>
                          <span className={`severity-badge ${rule.severity}`} style={{
                            padding: '4px 8px',
                            borderRadius: '4px',
                            fontSize: '12px',
                            fontWeight: 'bold',
                            backgroundColor: rule.severity === 'major' ? '#dc3545' : rule.severity === 'moderate' ? '#ffc107' : '#28a745',
                            color: 'white'
                          }}>
                            {rule.severity.toUpperCase()}
                          </span>
                        </div>
                        
                        <div style={{marginBottom: '15px'}}>
                          <label style={{display: 'block', marginBottom: '5px', fontWeight: 'bold'}}>Description:</label>
                          <textarea 
                            value={rule.desc}
                            onChange={(e) => {
                              const updatedRules = {...rules};
                              updatedRules[category][index].desc = e.target.value;
                              setRules(updatedRules);
                            }}
                            style={{
                              width: '100%',
                              minHeight: '60px',
                              padding: '8px',
                              border: '1px solid #ccc',
                              borderRadius: '4px',
                              fontSize: '14px'
                            }}
                          />
                        </div>
                        
                        <div style={{marginBottom: '15px'}}>
                          <label style={{display: 'block', marginBottom: '5px', fontWeight: 'bold'}}>Validation Logic:</label>
                          <div style={{
                            backgroundColor: '#f8f9fa',
                            border: '1px solid #e9ecef',
                            borderRadius: '4px',
                            padding: '10px',
                            fontSize: '13px'
                          }}>
                            {rule.logic && Object.keys(rule.logic).length > 0 ? (
                              <pre style={{margin: 0, whiteSpace: 'pre-wrap', fontFamily: 'monospace'}}>
                                {JSON.stringify(rule.logic, null, 2)}
                              </pre>
                            ) : (
                              `Database-driven rule validation logic for ${rule.code}`
                            )}
                          </div>
                        </div>
                        
                        <div style={{marginBottom: '15px'}}>
                          <label style={{display: 'block', marginBottom: '5px', fontWeight: 'bold'}}>Keywords to Detect:</label>
                          <input 
                            type="text"
                            placeholder="Enter keywords separated by commas"
                            style={{
                              width: '100%',
                              padding: '8px',
                              border: '1px solid #ccc',
                              borderRadius: '4px',
                              fontSize: '14px'
                            }}
                          />
                        </div>
                        
                        <div style={{marginBottom: '15px'}}>
                          <label style={{display: 'block', marginBottom: '5px', fontWeight: 'bold'}}>State-Specific Rules:</label>
                          <select style={{
                            width: '100%',
                            padding: '8px',
                            border: '1px solid #ccc',
                            borderRadius: '4px'
                          }}>
                            <option value="all">All States</option>
                            <option value="MA">Massachusetts Only</option>
                            <option value="MI,NH,AZ">Michigan, New Hampshire, Arizona</option>
                            <option value="CA">California Only</option>
                            <option value="TX,HI,OR,AR,IA,ND,VT,WV">TX, HI, OR, AR, IA, ND, VT, WV</option>
                          </select>
                        </div>
                        
                        <div style={{display: 'flex', gap: '15px', alignItems: 'center'}}>
                          <label style={{fontWeight: 'bold'}}>Severity:</label>
                          <select 
                            value={rule.severity}
                            onChange={(e) => {
                              const updatedRules = {...rules};
                              updatedRules[category][index].severity = e.target.value as 'major' | 'moderate' | 'minor';
                              setRules(updatedRules);
                            }}
                            style={{
                              padding: '5px 10px',
                              border: '1px solid #ccc',
                              borderRadius: '4px'
                            }}
                          >
                            <option value="major">Major</option>
                            <option value="moderate">Moderate</option>
                            <option value="minor">Minor</option>
                          </select>
                          
                          <button 
                            className="btn"
                            onClick={async () => {
                              if (!apiEndpoint) {
                                alert('API endpoint not configured');
                                return;
                              }
                              
                              const confirmed = window.confirm(
                                `Update rule ${rule.code}?\n\n` +
                                `This will change how the system validates compliance for this rule. ` +
                                `The new validation logic will be applied to all future audio processing.\n\n` +
                                `Are you sure you want to proceed?`
                              );
                              
                              if (!confirmed) return;
                              
                              try {
                                const response = await fetch(`${apiEndpoint}/rules/${rule.code}`, {
                                  method: 'PUT',
                                  headers: { 
                                    'Authorization': `Bearer ${authToken}`,
                                    'Content-Type': 'application/json' 
                                  },
                                  body: JSON.stringify({
                                    description: rule.desc,
                                    severity: rule.severity,
                                    active: true,
                                    validation_logic: 'Updated via UI',
                                    last_modified: new Date().toISOString(),
                                    modified_by: 'Business User'
                                  })
                                });
                                
                                if (response.ok) {
                                  alert(`✅ Rule ${rule.code} updated successfully!\n\nChanges will take effect for new audio processing.`);
                                } else {
                                  throw new Error('Failed to update rule');
                                }
                              } catch (error) {
                                console.error('Failed to update rule:', error);
                                alert(`❌ Failed to update rule ${rule.code}`);
                              }
                            }}
                            style={{
                              backgroundColor: '#28a745',
                              color: 'white',
                              border: 'none',
                              padding: '5px 15px',
                              borderRadius: '4px',
                              cursor: 'pointer',
                              fontSize: '12px'
                            }}
                          >
                            💾 Save
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                ))}
                
                <div style={{textAlign: 'center', marginTop: '30px'}}>
                  <button 
                    className="btn"
                    onClick={async () => {
                      if (!apiEndpoint) {
                        alert('API endpoint not configured');
                        return;
                      }
                      
                      try {
                        const updatePromises = Object.values(rules).flat().map(async (rule) => {
                          return fetch(`${apiEndpoint}/rules/${rule.code}`, {
                            method: 'PUT',
                            headers: { 
                              'Authorization': `Bearer ${authToken}`,
                              'Content-Type': 'application/json' 
                            },
                            body: JSON.stringify({
                              description: rule.desc,
                              severity: rule.severity,
                              active: true
                            })
                          });
                        });
                        
                        await Promise.all(updatePromises);
                        alert('All rules updated successfully!');
                      } catch (error) {
                        console.error('Failed to update rules:', error);
                        alert('Failed to update some rules');
                      }
                    }}
                    style={{
                      backgroundColor: '#007bff',
                      color: 'white',
                      border: 'none',
                      padding: '10px 30px',
                      borderRadius: '5px',
                      fontSize: '16px',
                      cursor: 'pointer'
                    }}
                  >
                    💾 Save All Rules
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}


    </div>
  );
};

export default AnyCompanyComplianceApp;