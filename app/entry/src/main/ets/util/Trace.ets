/**
 * 极简落盘日志。
 *
 * 为什么需要它：应用崩溃时系统日志（/data/log/faultlog）普通应用无权限读取，
 * 排查取图这类端侧问题只能自己把关键节点写进私有目录，事后用 hdc file recv 拉出来。
 * 只记录流程节点与错误类型，不记录用户内容。
 */

import { fileIo as fs } from '@kit.CoreFileKit';

const FILE_NAME = 'trace.log';
const MAX_BYTES = 256 * 1024;

export class Trace {
  private static filePath: string = '';

  static init(filesDir: string): void {
    Trace.filePath = filesDir + '/' + FILE_NAME;
    Trace.write('boot', 'trace started');
  }

  static write(tag: string, message: string): void {
    if (Trace.filePath.length === 0) {
      return;
    }
    try {
      const stat = fs.statSync(Trace.filePath);
      if (stat.size > MAX_BYTES) {
        fs.unlinkSync(Trace.filePath);
      }
    } catch (error) {
      // 文件还不存在，正常
    }
    try {
      const line = `${new Date().toISOString()} [${tag}] ${message}\n`;
      const file = fs.openSync(
        Trace.filePath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND
      );
      fs.writeSync(file.fd, line);
      fs.closeSync(file);
    } catch (error) {
      // 日志失败不能影响主流程
    }
  }

  static path(): string {
    return Trace.filePath;
  }
}
