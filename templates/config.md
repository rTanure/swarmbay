---
mobile_first: "?"        # yes | no | ?   (? = ainda não perguntado ao usuário)
mobile_usability: "?"    # só quando mobile_first=no: app | modulos | none | ?
---

# Perfil do projeto

Respostas do usuário que condicionam o trabalho de frontend. O orquestrador pergunta no início e grava aqui; não decida por conta própria.

## Regras derivadas

- `mobile_first: yes` → o layout nasce no mobile (artboard mobile é o principal, desktop é derivado); CSS/estrutura de baixo para cima; testes e revisão de layout cobrem viewport mobile.
- `mobile_first: no` e `mobile_usability: app` → a usabilidade em dispositivos móveis é requisito de todo o app, sem ser mobile first.
- `mobile_first: no` e `mobile_usability: modulos` → só os módulos listados abaixo exigem usabilidade mobile.
- `mobile_first: no` e `mobile_usability: none` → desktop apenas.

## Módulos com usabilidade mobile
(preenchido quando `mobile_usability: modulos`; pergunte ao usuário a cada módulo novo ainda não listado)

| módulo | mobile |
|---|---|
