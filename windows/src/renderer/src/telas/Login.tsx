// O portão do app (app/Sources/JFY/Login.swift e PrimeirosPassos.swift no Mac): só entra com a conta da Souv, e os
// primeiros passos guiam o resto. Ainda por trazer: por enquanto deixa entrar.
import type { ReactNode } from 'react'

export default function Portao({ children }: { children: ReactNode }) {
  return <>{children}</>
}
