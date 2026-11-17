import { expect, test } from '@playwright/test'

const CORREO = process.env.WINOPO_OPOSITOR ?? 'opositor.a@ejemplo.test'
const CLAVE = process.env.WINOPO_CLAVE ?? 'clave-sintetica-A1'

test.describe('F0 · acceso y aislamiento', () => {
  test('la portada carga y ofrece acceder', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByRole('heading', { level: 1 })).toContainText('preparador')
    await expect(page.getByRole('link', { name: 'Acceder' })).toBeVisible()
  })

  test('sin sesión, el panel del preparador redirige a login', async ({ page }) => {
    await page.goto('/preparador')
    await expect(page).toHaveURL(/\/login$/)
  })

  test('con credenciales incorrectas se muestra un error y no se entra', async ({ page }) => {
    await page.goto('/login')
    await page.getByLabel('Correo').fill(CORREO)
    await page.getByLabel('Contraseña').fill('clave-incorrecta')
    await page.getByRole('button', { name: 'Entrar' }).click()
    await expect(page.getByRole('alert')).toContainText('credenciales incorrectas')
    await expect(page).toHaveURL(/\/login$/)
  })

  test('el opositor entra y aterriza en su panel', async ({ page }) => {
    await page.goto('/login')
    await page.getByLabel('Correo').fill(CORREO)
    await page.getByLabel('Contraseña').fill(CLAVE)
    await page.getByRole('button', { name: 'Entrar' }).click()
    await expect(page).toHaveURL(/\/opositor$/)
    await expect(page.getByRole('heading', { level: 1 })).toContainText('Mi preparación')
  })

  test('el opositor no puede abrir el panel del preparador', async ({ page }) => {
    await page.goto('/login')
    await page.getByLabel('Correo').fill(CORREO)
    await page.getByLabel('Contraseña').fill(CLAVE)
    await page.getByRole('button', { name: 'Entrar' }).click()
    await expect(page).toHaveURL(/\/opositor$/)

    await page.goto('/preparador')
    await expect(page).toHaveURL(/\/opositor$/)
  })
})
