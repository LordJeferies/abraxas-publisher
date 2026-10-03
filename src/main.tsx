import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './styles.css'
import { registerPwa } from './pwa'
import {
  initializePublisherSync,
} from './lib/publisherSync'

import {
  initializeBackend,
} from './lib/backend'


ReactDOM.createRoot(document.getElementById('root')!).render(<React.StrictMode><App/></React.StrictMode>)


registerPwa()


initializeBackend()
  .then(
    () =>
      initializePublisherSync(),
  )
  .catch(
    console.error,
  )
