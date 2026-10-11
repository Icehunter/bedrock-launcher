import { HashRouter, Navigate, Route, Routes } from "react-router-dom";
import Layout from "./components/Layout";
import Home from "./pages/Home";
import Install from "./pages/Install";
import Guide from "./pages/Guide";
import Faq from "./pages/Faq";
import Releases from "./pages/Releases";

export default function App() {
  return (
    <HashRouter>
      <Routes>
        <Route element={<Layout />}>
          <Route index element={<Home />} />
          <Route path="install" element={<Install />} />
          <Route path="guide" element={<Guide />} />
          <Route path="faq" element={<Faq />} />
          <Route path="releases" element={<Releases />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Route>
      </Routes>
    </HashRouter>
  );
}
