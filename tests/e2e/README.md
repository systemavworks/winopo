# Pruebas de extremo a extremo

Se ejecutan contra el stack levantado (`make dev` + `make migrate`), nunca contra producción.

Flujos previstos, uno por fase:

| Fase | Flujo |
|---|---|
| F0 | Alta de preparador y de opositor; el opositor del tenant A no ve nada del tenant B |
| F1 | Publicar tema v1, editar a v2, comprobar que el opositor ve v2 y el histórico sigue |
| F2 | Test de 30 preguntas, nota en céntimos y desglose por tema |
| F3 | Entrega de supuesto, corrección IA, validación del preparador y nota final |
| F4 | Generar vídeo de un tema y marcarlo desactualizado al cambiar de versión |
| F5 | Compra de prueba, webhook, acceso concedido y consentimiento guardado |

Hoy: **vacío a propósito**. `make e2e` falla con un mensaje explícito hasta que exista el primer flujo.
