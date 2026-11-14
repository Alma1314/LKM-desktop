/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Script for compiling build behavior. It is built in the build plug-in and cannot be modified currently.
import { harTasks } from '@ohos/hvigor-ohos-plugin';

const { execSync } = require('node:child_process');

export function rustPluginFunction(str?: string) {
  return {
    pluginId: 'CustomPluginID1',
    apply(pluginContext) {
      //注册自定义任务 接口pluginContext 方法registerTask
      pluginContext.registerTask({
        // 编写自定义任务
        name: 'rustTask',
        run: (taskContext) => {
          // taskContext.moduleName;
          // taskContext.modulePath;
          //接口 taskContext  模块名称 moduleName 模块的绝对路径 modulePath
          console.log('build super_native_extensions library...');
          console.log('moduleName is '+ taskContext.moduleName + ' modulePath is ' + taskContext.modulePath + '.');
          try {
            let cmd: string = '';
            const os = require('os');
            if (os.type() == 'Windows_NT') {
              console.log('build rust library...  host os is windows');
              cmd = 'pushd ' + taskContext.modulePath + '\\..\\..\\super_native_extensions\\cargokit ' + '&& '
                + '.\\build_ohos.bat && popd';
            } else {
              console.log('build rust library...  host os is not windows');
              cmd = 'cd ' + taskContext.modulePath + '/../../super_native_extensions/cargokit' + '&&'
                + './build_ohos.sh' + '&& cd -';
            }
            console.log('cmd is ' + cmd);
            execSync(cmd, {
                maxBuffer: 1024 * 2000
            });
            // console.log(stdout);
            console.log('build super_native_extensions rust library success.');
          } catch (err) {
            if (err.code) {
              // Spawning child process failed
              console.error(err.code);
            } else {
              // Child was spawned but exited with non-zero exit code
              // Error contains any stdout and stderr from the child
              const { stdout, stderr } = err;
              console.error({ stdout, stderr });
            }
            console.log('build super_native_extensions rust library failed.');
          }
        },
        // 确认自定义任务插入位置
        // dependencies: ['default@BuildJS'],
        dependencies: ['default@PreBuild'],
        // postDependencies: ['default@CompileArkTS']
        postDependencies: ['default@ProcessOHPackageJson']
      })
    }
  }
}

export default {
  system: harTasks, // Hvigor内置插件，不可修改
  plugins: [rustPluginFunction()]       // 自定义插件
}