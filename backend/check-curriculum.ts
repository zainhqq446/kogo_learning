import { getDbPool, closeDbPool } from "./src/config/database.js";

async function main() {
  const pool = getDbPool();

  try {
    const result = await pool.query(`
      SELECT
        (SELECT COUNT(*) FROM stages) AS stages,
        (SELECT COUNT(*) FROM lessons) AS lessons,
        (SELECT COUNT(*) FROM questions) AS questions
    `);

    console.log("HASIL KURIKULUM:", result.rows[0]);
  } finally {
    await closeDbPool();
  }
}

main().catch((error) => {
  console.error("Pemeriksaan gagal:", error.message);
  process.exitCode = 1;
});
