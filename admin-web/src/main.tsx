import React, { Suspense, lazy } from 'react';
import ReactDOM from 'react-dom/client';
import './styles.css';

const RootApp = window.location.pathname.startsWith('/admin')
  ? lazy(() => import('./App'))
  : lazy(() => import('./UserApp'));

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Suspense fallback={<div className="boot-screen">Đang mở Omninary Web</div>}>
      <RootApp />
    </Suspense>
  </React.StrictMode>
);
